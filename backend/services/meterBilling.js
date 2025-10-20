// backend/services/meterBilling.js
require('dotenv').config();
const { TuyaOpenAPI } = require('@tuya/tuya-connector-nodejs');
const admin = require('firebase-admin');
const pLimit = require('p-limit');

if (!admin.apps.length) {
  try {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
  } catch (_) {
    // ถ้าไม่มี credential ไว้ก่อน ใช้งานเฉพาะตอนส่งแจ้งเตือนจริง
  }
}

function toKV(statusArr) {
  const kv = {};
  (statusArr || []).forEach(s => { kv[s.code] = s.value; });
  return kv;
}

async function sendFCM(db, userId, title, body, data = {}) {
  if (!admin?.messaging) return;
  const { rows } = await db.query('SELECT fcm_token FROM user_devices WHERE user_id=$1', [userId]);
  const tokens = rows.map(r => r.fcm_token).filter(Boolean);
  if (!tokens.length) return;
  await admin.messaging().sendEachForMulticast({ tokens, notification: { title, body }, data });
}

async function getApiClient(map, regionHost, accessId, accessKey) {
  if (map.has(regionHost)) return map.get(regionHost);
  const cli = new TuyaOpenAPI(`https://${regionHost}`, accessId, accessKey);
  await cli.connect();
  map.set(regionHost, cli);
  return cli;
}

/**
 * options: {
 *   scope: { meterId?, buildingId?, ownerId? }   // ไม่ระบุ = ทั้งหมด
 *   dryRun?: boolean,                            // true = ไม่เขียน DB/ไม่ยิงคำสั่ง
 *   parallel?: number                            // ค่าเริ่มต้น 5
 * }
 * returns: { scanned, updated, cut, lowNoti, criticalNoti, errors: [] }
 */
async function runMeterBilling(db, options = {}) {
  const { scope = {}, dryRun = false, parallel = 5 } = options;
  const AID = process.env.TUYA_ACCESS_ID;
  const AKEY = process.env.TUYA_ACCESS_KEY;

  const where = [];
  const params = [];
  if (scope.meterId) { params.push(scope.meterId); where.push(`td.id = $${params.length}`); }
  if (scope.buildingId) { params.push(scope.buildingId); where.push(`b."BuildingID" = $${params.length}`); }
  if (scope.ownerId) { params.push(scope.ownerId); where.push(`b."OwnerID" = $${params.length}`); }

  const sql = `
  SELECT
    td.*,
    td."DeviceID",
    td."RoomNumber" AS room_no,
    b."BuildingID"  AS building_id,
    (td.dp_map->>'total_kwh') AS dp_total_kwh,
    (td.dp_map->>'switch')    AS dp_switch,
    NULL AS tuya_region
  FROM "TuyaDevice" td
  LEFT JOIN "Room" r
    ON r."RoomNumber" = td."RoomNumber"
  LEFT JOIN "Building" b
    ON b."BuildingID" = r."BuildingID"
  ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
`;
  const meters = (await db.query(sql, params)).rows;


  const summary = { scanned: meters.length, updated: 0, cut: 0, lowNoti: 0, criticalNoti: 0, errors: [] };
  const regionMap = new Map();
  const limit = pLimit(parallel);

  await Promise.all(meters.map(m => limit(async () => {
    try {
      const region = m.tuya_region || 'openapi.tuyaeu.com'; // ปรับ default ให้ตรงระบบคุณ
      const api = await getApiClient(regionMap, region, AID, AKEY);

      // 1) อ่านสถานะอุปกรณ์
      const st = await api.get(`/v1.0/devices/${m.DeviceID}/status`);
      const kv = toKV(st.result);
      const total = Number(kv[m.dp_total_kwh]);
      if (!isFinite(total)) return;

      // อ่านค่าก่อนหน้า (ใช้ EnergyKwh)
      const prev = await db.query(`
  SELECT "EnergyKwh" FROM "ElectricReading"
  WHERE "DeviceID"=$1
  ORDER BY "At" DESC
  LIMIT 1
`, [m.DeviceID]);
      const prevTotal = prev.rows[0]?.EnergyKwh ?? null;

      // บันทึกค่าอ่านล่าสุด (เก็บ total ลง EnergyKwh)
      if (!dryRun) {
        await db.query(`
    INSERT INTO "ElectricReading" ("DeviceID","At","EnergyKwh","Raw")
    VALUES ($1, now(), $2, $3)
    ON CONFLICT ("DeviceID","At") DO NOTHING
  `, [m.DeviceID, total, JSON.stringify(st.result)]);
      }

      summary.updated++;

      // 4) เครดิตคงเหลือ
      const creditRes = await db.query(`SELECT credit_kwh FROM meter_credit_v WHERE meter_id=$1`, [m.id]);
      const credit = Number(creditRes.rows[0]?.credit_kwh ?? 0);
      const low = Number(m.threshold_low_kwh ?? 2);
      const critical = Number(m.threshold_critical_kwh ?? 0.5);
      const reconnectMin = Number(m.reconnect_min_kwh ?? 0.5);

      // หา tenant ปัจจุบัน (ปรับ query ให้ตรง schema คุณ)
      let tenantId = null;
      try {
const t = await db.query(`SELECT "TenantID" FROM "Tenant" WHERE "RoomNumber"=$1 AND "IsActive"=TRUE LIMIT 1`, [m.room_no]);        tenantId = t.rows[0]?.TenantID || null;
      } catch (_) { }

      // 5) แจ้งเตือน
      if (credit <= low && !dryRun && tenantId) {
        const can = !m.last_low_notified_at || (Date.now() - new Date(m.last_low_notified_at).getTime()) > 12 * 3600e3;
        if (can) {
          await sendFCM(db, tenantId, 'หน่วยไฟฟ้าใกล้หมด', `คงเหลือ ${credit.toFixed(2)} kWh กรุณาซื้อเพิ่ม`, { meter_id: String(m.id) });
          await db.query(`UPDATE "TuyaDevice" SET last_low_notified_at=now() WHERE id=$1`, [m.id]);
          summary.lowNoti++;
        }
      }
      if (credit <= critical && !dryRun && tenantId) {
        const can = !m.last_critical_notified_at || (Date.now() - new Date(m.last_critical_notified_at).getTime()) > 6 * 3600e3;
        if (can) {
          await sendFCM(db, tenantId, 'หน่วยไฟฟ้าวิกฤติ', `คงเหลือ ${credit.toFixed(2)} kWh`, { meter_id: String(m.id) });
          await db.query(`UPDATE "TuyaDevice" SET last_critical_notified_at=now() WHERE id=$1`, [m.id]);
          summary.criticalNoti++;
        }
      }

      // 6) เครดิตหมด → ตัด
      if (credit <= 0 && m.is_cut === false && m.dp_switch) {
        if (!dryRun) {
          await api.post(`/v1.0/devices/${m.DeviceID}/commands`, { commands: [{ code: m.dp_switch, value: false }] });
          await db.query(`UPDATE "TuyaDevice" SET is_cut=TRUE, last_cut_at=now() WHERE id=$1`, [m.id]);
        }
        summary.cut++;
      }

      // 7) (ทางกลับ) — ให้ route เติมเงินเรียกอีกฟังก์ชัน reconnect เองเมื่อซื้อหน่วยสำเร็จ

    } catch (e) {
      summary.errors.push({ meterId: m.id, deviceId: m.DeviceID, error: e?.response?.data || e.message });
    }
  })));

  return summary;
}

module.exports = { runMeterBilling };
