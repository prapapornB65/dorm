// routes/tenant/tenant-usage.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();
  const isPg = typeof db.any === 'function';
  const qAny = (q, p = []) => isPg ? db.any(q, p) : db.query(q, p).then(r => r.rows);
  const qOne = (q, p = []) => isPg ? db.oneOrNone(q, p) : db.query(q, p).then(r => r.rows[0] || null);

  // ---- timezone-safe date helpers ----
  const pad2 = (n) => String(n).padStart(2, '0');
  const ymd  = (d) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;

  // GET /api/tenant/:tenantId/usage/series?months=12
  router.get('/tenant/:tenantId/usage/series', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    const months = Math.max(1, Math.min(24, Number(req.query.months || 12)));
    if (!Number.isInteger(tenantId) || tenantId <= 0) {
      return res.status(400).json({ error: 'bad tenantId' });
    }

    // ห้อง + ตึกของผู้เช่าล่าสุด
    const who = await qOne(`
      SELECT t."RoomNumber" AS room, r."BuildingID" AS buildingId
      FROM "Tenant" t
      JOIN "Room" r ON r."RoomNumber" = t."RoomNumber"
      WHERE t."TenantID" = $1
      ORDER BY t."Start" DESC
      LIMIT 1
    `, [tenantId]);

    if (!who?.room || !who?.buildingId) return res.json({ items: [] });

    const room = who.room;
    const buildingId = who.buildingId;

    // เตรียมช่วง 12 เดือน (จบด้วยเดือนปัจจุบัน)
    const base = new Date();
    const first = new Date(base.getFullYear(), base.getMonth() - (months - 1), 1);

    const items = [];
    for (let i = 0; i < months; i++) {
      const s  = new Date(first.getFullYear(), first.getMonth() + i, 1);     // start of month
      const e  = new Date(first.getFullYear(), first.getMonth() + i + 1, 1); // start of next month
      const ym = `${s.getFullYear()}-${pad2(s.getMonth() + 1)}`;

      // เรท ณ รอบบิล (ยึดตึกของผู้เช่า และใช้วันสิ้นรอบ: e)
      const rateRow = await qOne(`
        SELECT "ElectricUnitPrice" AS e_rate, "WaterUnitPrice" AS w_rate
        FROM "UtilityRate"
        WHERE "BuildingID" = $1 AND "EffectiveDate" <= $2::date
        ORDER BY "EffectiveDate" DESC
        LIMIT 1
      `, [buildingId, ymd(e)]);
      const eRate = Number(rateRow?.e_rate || 0); // บาท/kWh
      const wRate = Number(rateRow?.w_rate || 0); // บาท/ลิตร

      // ---------- ไฟฟ้า: ใช้เลขสะสมต้น/ปลาย ----------
      const erow = await qOne(`
        WITH first_last AS (
          SELECT
            COALESCE(
              (SELECT "EnergyKwh" FROM "ElectricReading"
               WHERE "RoomNumber"=$1 AND (kind='electric' OR kind IS NULL) AND "At"<$2
               ORDER BY "At" DESC LIMIT 1),
              (SELECT "EnergyKwh" FROM "ElectricReading"
               WHERE "RoomNumber"=$1 AND (kind='electric' OR kind IS NULL) AND "At">=$2 AND "At"<$3
               ORDER BY "At" ASC  LIMIT 1)
            ) AS s_kwh,
            (SELECT "EnergyKwh" FROM "ElectricReading"
             WHERE "RoomNumber"=$1 AND (kind='electric' OR kind IS NULL) AND "At"<$3
             ORDER BY "At" DESC LIMIT 1) AS e_kwh
        ) SELECT * FROM first_last
      `, [room, ymd(s), ymd(e)]);
      const sK = Number(erow?.s_kwh || 0);
      const eK = Number(erow?.e_kwh || 0);
      const usedKwh = Math.max(0, eK - sK);
      const electricAmount = Number((usedKwh * eRate).toFixed(2));

      // ---------- น้ำ: ลิตรสะสมต้น/ปลาย (คิดเงินบาท/ลิตร) ----------
      const wrow = await qOne(`
        WITH first_last AS (
          SELECT
            COALESCE(
              (SELECT "TotalLiters" FROM "ElectricReading"
               WHERE "RoomNumber"=$1 AND kind='water' AND "At"<$2
               ORDER BY "At" DESC LIMIT 1),
              (SELECT "TotalLiters" FROM "ElectricReading"
               WHERE "RoomNumber"=$1 AND kind='water' AND "At">=$2 AND "At"<$3
               ORDER BY "At" ASC  LIMIT 1)
            ) AS s_liters,
            (SELECT "TotalLiters" FROM "ElectricReading"
             WHERE "RoomNumber"=$1 AND kind='water' AND "At"<$3
             ORDER BY "At" DESC LIMIT 1) AS e_liters
        ) SELECT * FROM first_last
      `, [room, ymd(s), ymd(e)]);
      let sL = Number(wrow?.s_liters || 0);
      let eL = Number(wrow?.e_liters || 0);
      let usedLiters = Math.max(0, eL - sL);

      // Fallback: ถ้าไม่มี TotalLiters ให้ integrate จาก FlowLpm
      if (usedLiters === 0) {
        const integ = await qOne(`
          WITH rows AS (
            SELECT "At","FlowLpm"
            FROM "ElectricReading"
            WHERE "RoomNumber"=$1 AND kind='water'
              AND "At">=$2 AND "At"<$3
            ORDER BY "At" ASC
          ),
          seg AS (
            SELECT "At","FlowLpm",
                   LEAD("At") OVER (ORDER BY "At") AS next_at,
                   LEAD("FlowLpm") OVER (ORDER BY "At") AS next_flow
            FROM rows
          )
          SELECT COALESCE(SUM(((EXTRACT(EPOCH FROM (COALESCE(next_at,"At")-"At"))/60.0)
                               * (("FlowLpm"+COALESCE(next_flow,"FlowLpm"))/2.0))),0) AS used_liters
          FROM seg
        `, [room, ymd(s), ymd(e)]);
        usedLiters = Number(integ?.used_liters || 0);
      }

      const waterAmount = Number((usedLiters * wRate).toFixed(2)); // บาท/ลิตร

      // สถานะชำระ: เทียบกับเดือน "s" (เดือนนี้)
      const pay = await qOne(`
        SELECT 1
        FROM "Payment"
        WHERE "TenantID"=$1
          AND DATE_TRUNC('month', "PaymentDate") = DATE_TRUNC('month', $2::timestamp)
          AND UPPER(COALESCE("Status",'')) IN ('PAID','VERIFIED','ตรวจสอบแล้ว')
        LIMIT 1
      `, [tenantId, ymd(s)]);
      const status = pay ? 'paid' : 'unpaid';

      items.push({
        month: ym,
        electricKWh: Number(usedKwh.toFixed(2)),
        waterLiters: Number(usedLiters.toFixed(1)), // ลิตร (ทศนิยม 1 ตำแหน่ง)
        electricAmount,
        waterAmount,
        status,
      });
    }

    res.json({
      unit: { waterVolume: 'L', waterBilling: 'THB_per_L', electricBilling: 'THB_per_kWh' },
      items
    });
  });

  return router;
};
