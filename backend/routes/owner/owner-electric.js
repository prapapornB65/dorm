// routes/owner/owner-electric.js
const express = require('express');
const { getDeviceStatus, sendDeviceCommand } = require('../../services/tuyaClient');

module.exports = function ownerElectricRoutes(db, requireAuth) {
  const router = express.Router();
  const isPgPromise = typeof db.any === 'function';
  const qAny = (t, p = []) => isPgPromise ? db.any(t, p) : db.query(t, p).then(r => r.rows);
  const qOne = (t, p = []) => isPgPromise ? db.oneOrNone(t, p) : db.query(t, p).then(r => r.rows[0] || null);
  const qNone = (t, p = []) => isPgPromise ? db.none(t, p) : db.query(t, p).then(() => null);

  // ---------- helpers ----------
  const parsePositiveInt = (v) => { const n = Number(v); return Number.isInteger(n) && n > 0 ? n : null; };
  const ensureBuildingId = (req, res, next) => {
    const b = parsePositiveInt(req.params.buildingId ?? req.query.buildingId);
    if (!b) return res.status(400).json({ error: 'buildingId must be a positive integer' });
    req.buildingId = b; next();
  };
  const pick = (obj, keys = []) => { for (const k of keys) if (obj[k] !== undefined && obj[k] !== null) return obj[k]; };
  const TUYA_CONCURRENCY = Number(process.env.TUYA_CONCURRENCY || 3);
  const TUYA_PER_DEVICE_TIMEOUT_MS = Number(process.env.TUYA_PER_DEVICE_TIMEOUT_MS || 8000);

  function withTimeout(promise, ms) {
    return Promise.race([
      promise,
      new Promise((_, rej) => setTimeout(() => rej(new Error('TUYA_TIMEOUT')), ms)),
    ]);
  }

  async function runLimited(items, limit, worker) {
    const running = new Set();
    const results = new Array(items.length);
    let i = 0;

    async function kick() {
      if (i >= items.length) return;
      const idx = i++;
      const p = worker(items[idx])
        .then(r => { results[idx] = r; })
        .catch(e => { results[idx] = e; })
        .finally(() => running.delete(p));
      running.add(p);
      if (running.size >= limit) await Promise.race(running);
      return kick();
    }

    await kick();
    await Promise.allSettled([...running]);
    return results;
  }

  // ===== occupied rooms =====
  router.get('/buildings/:buildingId/occupied-rooms', requireAuth, ensureBuildingId, async (req, res) => {
    const b = req.buildingId;
    const rows = await qAny(`
      SELECT DISTINCT r."RoomNumber"
      FROM "Room" AS r
      JOIN "Tenant" AS t
        ON t."RoomNumber" = r."RoomNumber"
       AND (t."End" IS NULL OR t."End" > NOW())
      WHERE r."BuildingID" = $1
      ORDER BY r."RoomNumber" ASC
    `, [b]);
    res.json({ items: rows.map(r => r.RoomNumber) });
  });

  // ===== meters list =====
  // ===== meters (รายการมิเตอร์) =====
  async function metersHandler(req, res) {
    const b = req.buildingId;
    const devices = await qAny(`
    SELECT td."DeviceID" AS deviceId,
           td."RoomNumber" AS roomNumber,
           td.device_kind AS type,
           COALESCE(td.name, td."DeviceID") AS label
    FROM "TuyaDevice" AS td
    JOIN "Room" AS r
      ON r."RoomNumber" = td."RoomNumber" AND r."BuildingID" = td.building_id
    WHERE r."BuildingID" = $1 AND COALESCE(td."Active", FALSE) IS TRUE
    ORDER BY td."RoomNumber" ASC
  `, [b]);

    const out = [];
    for (const d of devices) {
      let at = null;
      let kwh = null;
      let liters = null;  // <<< เปลี่ยนมาเก็บลิตร

      if (d.type === 'electric') {
        const r = await qOne(`
        SELECT "EnergyKwh" AS kwh, "At" AS at
        FROM "ElectricReading"
        WHERE "DeviceID" = $1 AND (kind IS NULL OR kind = 'electric')
          AND "EnergyKwh" IS NOT NULL AND "EnergyKwh" > 0
        ORDER BY "At" DESC
        LIMIT 1
      `, [d.deviceId]);
        if (r) { kwh = Number(r.kwh); at = r.at; }
      } else {
        const r = await qOne(`
        SELECT "TotalLiters" AS liters, "At" AS at
        FROM "ElectricReading"
        WHERE "DeviceID" = $1 AND kind = 'water'
          AND "TotalLiters" IS NOT NULL AND "TotalLiters" > 0
        ORDER BY "At" DESC
        LIMIT 1
      `, [d.deviceId]);
        if (r) { liters = Number(r.liters); at = r.at; } // <<< ส่งค่าเป็นลิตรตรง ๆ
      }

      out.push({
        meterId: d.deviceId,
        deviceId: d.deviceId,
        roomNumber: d.roomNumber,
        type: d.type,        // 'electric' | 'water'
        label: d.label,
        relay_on: null,
        kwh,                 // ไฟฟ้า: kWh
        liters,              // น้ำ: ลิตร  <<< key ใหม่แทน m3
        updatedAt: at
      });
    }

    res.json({ items: out });
  }
  router.get('/owner-electric/meters', requireAuth, ensureBuildingId, metersHandler);
  router.get('/building/:buildingId/meters', requireAuth, ensureBuildingId, metersHandler);

  // ===== utility rate (get/put) =====
  // ===== utility rate (get/put) =====
  // ===== utility rate (get/put) =====
  // GET: คืนเรท โดยระบุหน่วยชัดเจน (น้ำ = บาท/ลิตร)
  router.get('/building/:buildingId/utility-rate', requireAuth, ensureBuildingId, async (req, res) => {
    const b = req.buildingId;
    const row = await qOne(`
    SELECT "ElectricUnitPrice" AS electricUnitPrice,
           "WaterUnitPrice"   AS waterUnitPrice,   -- เก็บเป็น "บาท/ลิตร"
           "EffectiveDate"    AS effectiveDate
    FROM "UtilityRate"
    WHERE "BuildingID" = $1
    ORDER BY "EffectiveDate" DESC
    LIMIT 1
  `, [b]);

    if (!row) {
      return res.json({
        electricUnitPrice: 0,
        electricPriceUnit: 'THB_per_kWh',
        waterUnitPrice: 0,
        waterPriceUnit: 'THB_per_L',
        effectiveDate: null
      });
    }

    res.json({
      electricUnitPrice: Number(row.electricUnitPrice || 0),
      electricPriceUnit: 'THB_per_kWh',
      waterUnitPrice: Number(row.waterUnitPrice || 0),  // ✅ บาท/ลิตร
      waterPriceUnit: 'THB_per_L',
      effectiveDate: row.effectiveDate
    });
  });

  // PUT: เหมือนเดิม (เก็บ WaterUnitPrice เป็น "บาท/ลิตร")
  router.put('/building/:buildingId/utility-rate', requireAuth, ensureBuildingId, async (req, res) => {
    const b = req.buildingId;
    const { electricUnitPrice, waterUnitPrice, effectiveDate } = req.body || {};

    await qNone(`
    INSERT INTO "UtilityRate"("BuildingID","ElectricUnitPrice","WaterUnitPrice","EffectiveDate")
    VALUES ($1,$2,$3,$4)
  `, [b, Number(electricUnitPrice || 0), Number(waterUnitPrice || 0), effectiveDate || new Date().toISOString().slice(0, 10)]);

    res.json({ ok: true });
  });



  // ===== charges (ไฟ) — มี fallback แบบ integrate และตัดโค้ดซ้ำทิ้ง =====
  router.get('/building/:buildingId/electric/charges', requireAuth, ensureBuildingId, async (req, res) => {
    const b = req.buildingId;
    const ym = String(req.query.month || '');
    if (!/^\d{4}-\d{2}$/.test(ym)) return res.status(400).json({ error: 'bad month (expect YYYY-MM)' });

    const monthStart = new Date(`${ym}-01T00:00:00.000Z`);
    const monthEnd = new Date(new Date(monthStart).setMonth(monthStart.getMonth() + 1));

    const rateRow = await qOne(`
    SELECT "ElectricUnitPrice" AS rate
    FROM "UtilityRate"
    WHERE "BuildingID" = $1 AND "EffectiveDate" <= $2::date
    ORDER BY "EffectiveDate" DESC LIMIT 1
  `, [b, monthEnd.toISOString().slice(0, 10)]);
    const rate = Number(rateRow?.rate || 0);

    const rooms = await qAny(`
    WITH dev AS (
      SELECT DISTINCT ON (td."RoomNumber") td."RoomNumber", td."DeviceID", td."id"
      FROM "TuyaDevice" td
      WHERE COALESCE(td."Active",FALSE) IS TRUE
        AND td.building_id = $1
        AND (td.device_kind='electric'
             OR (COALESCE(td.dp_map::jsonb,'{}'::jsonb) ? 'electric')
             OR NOT (COALESCE(td.dp_map::jsonb,'{}'::jsonb) ? 'water'))
      ORDER BY td."RoomNumber", td."id" DESC
    )
    SELECT DISTINCT r."RoomNumber", d."DeviceID"
    FROM "Room" r
    LEFT JOIN dev d ON d."RoomNumber" = r."RoomNumber"
    JOIN "Tenant" t ON t."RoomNumber" = r."RoomNumber"
                   AND (t."End" IS NULL OR t."End" > NOW())
    WHERE r."BuildingID" = $1
    ORDER BY r."RoomNumber" ASC
  `, [b]);

    const items = [];

    for (const r of rooms) {
      const dev = r.DeviceID;
      if (!dev) {
        items.push({
          roomNumber: r.RoomNumber,
          startKwh: 0, endKwh: 0, usedKwh: 0,
          pricePerUnit: rate, amount: 0,
          startAt: null, endAt: null
        });
        continue;
      }

      // 1) ใช้เลขสะสมก่อน
      const row = await qOne(`
      WITH first_last AS (
        SELECT
          COALESCE(
            (SELECT "EnergyKwh" FROM "ElectricReading"
             WHERE "DeviceID"=$1 AND kind='electric' AND "At"<$2
             ORDER BY "At" DESC LIMIT 1),
            (SELECT "EnergyKwh" FROM "ElectricReading"
             WHERE "DeviceID"=$1 AND kind='electric' AND "At">=$2 AND "At"<$3
             ORDER BY "At" ASC  LIMIT 1)
          ) AS start_kwh,
          (SELECT "EnergyKwh" FROM "ElectricReading"
           WHERE "DeviceID"=$1 AND kind='electric' AND "At"<$3
           ORDER BY "At" DESC LIMIT 1) AS end_kwh,
          (SELECT "At" FROM "ElectricReading"
           WHERE "DeviceID"=$1 AND kind='electric' AND "At"<$2
           ORDER BY "At" DESC LIMIT 1) AS start_at,
          (SELECT "At" FROM "ElectricReading"
           WHERE "DeviceID"=$1 AND kind='electric' AND "At"<$3
           ORDER BY "At" DESC LIMIT 1) AS end_at
      ) SELECT * FROM first_last
    `, [dev, monthStart.toISOString(), monthEnd.toISOString()]);

      let s = Number(row?.start_kwh || 0);
      let e = Number(row?.end_kwh || 0);
      let used = Math.max(0, e - s);
      let startAt = row?.start_at || null;
      let endAt = row?.end_at || null;

      // 2) ถ้าเลขสะสมใช้ไม่ได้ → integrate จาก PowerW
      if (used === 0) {
        const integ = await qOne(`
        WITH rows AS (
          SELECT "At","PowerW"
          FROM "ElectricReading"
          WHERE "DeviceID"=$1 AND kind='electric'
            AND "At">=$2 AND "At"<$3
          ORDER BY "At" ASC
        ),
        seg AS (
          SELECT "At","PowerW",
                 LEAD("At") OVER (ORDER BY "At") AS next_at,
                 LEAD("PowerW") OVER (ORDER BY "At") AS next_pw
          FROM rows
        )
        SELECT
          MIN("At") AS start_at,
          MAX(COALESCE(next_at,"At")) AS end_at,
          COALESCE(SUM(
            (EXTRACT(EPOCH FROM (COALESCE(next_at,"At") - "At"))/3600.0)
            * (("PowerW"+COALESCE(next_pw,"PowerW"))/2.0) / 1000.0
          ),0) AS used_kwh
        FROM seg
      `, [dev, monthStart.toISOString(), monthEnd.toISOString()]);

        used = Number(integ?.used_kwh || 0);
        s = 0;      // ให้ UI เข้าใจง่าย
        e = used;
        startAt = integ?.start_at || startAt;
        endAt = integ?.end_at || endAt;
      }

      const amount = Number((used * rate).toFixed(2));
      items.push({
        roomNumber: r.RoomNumber,
        startKwh: s, endKwh: e, usedKwh: used,
        pricePerUnit: rate, amount,
        startAt, endAt
      });
    }

    const totalKwh = items.reduce((a, b) => a + (Number(b.usedKwh) || 0), 0);
    const totalAmount = Number(items.reduce((a, b) => a + (Number(b.amount) || 0), 0).toFixed(2));
    res.json({ month: ym, rate, totalKwh, totalAmount, items });
  });


  // ===== charges (น้ำ) ===== — start/end + integrate fallback
  // ===== charges (น้ำ) — ใช้ลิตร และคิดเงินเป็น "บาท/ลิตร"
  router.get('/building/:buildingId/water/charges', requireAuth, ensureBuildingId, async (req, res) => {
    const b = req.buildingId;
    const ym = String(req.query.month || '');
    if (!/^\d{4}-\d{2}$/.test(ym)) return res.status(400).json({ error: 'bad month (expect YYYY-MM)' });

    const monthStart = new Date(`${ym}-01T00:00:00.000Z`);
    const monthEnd = new Date(new Date(monthStart).setMonth(monthStart.getMonth() + 1));

    // ดึงเรทราคา "บาท/ลิตร" ณ รอบบิล (ยึด effectiveDate ล่าสุดก่อนสิ้นเดือน)
    const rateRow = await qOne(`
    SELECT "WaterUnitPrice" AS price_per_liter
    FROM "UtilityRate"
    WHERE "BuildingID"=$1 AND "EffectiveDate" <= $2::date
    ORDER BY "EffectiveDate" DESC LIMIT 1
  `, [b, monthEnd.toISOString().slice(0, 10)]);
    const pricePerLiter = Number(rateRow?.price_per_liter || 0);

    // เลือกห้องที่มีอุปกรณ์น้ำ
    const rooms = await qAny(`
    WITH dev AS (
      SELECT DISTINCT ON (td."RoomNumber")
             td."RoomNumber", td."DeviceID", td."id"
      FROM "TuyaDevice" td
      WHERE COALESCE(td."Active",FALSE) IS TRUE
        AND td.building_id = $1
        AND (td.device_kind='water' OR (COALESCE(td.dp_map::jsonb,'{}'::jsonb) ? 'water'))
      ORDER BY td."RoomNumber", td."id" DESC
    )
    SELECT DISTINCT r."RoomNumber", d."DeviceID"
    FROM "Room" r
    LEFT JOIN dev d ON d."RoomNumber"=r."RoomNumber"
    JOIN "Tenant" t ON t."RoomNumber"=r."RoomNumber"
                   AND (t."End" IS NULL OR t."End" > NOW())
    WHERE r."BuildingID"=$1
    ORDER BY r."RoomNumber" ASC
  `, [b]);

    const items = [];
    for (const r of rooms) {
      const dev = r.DeviceID;
      if (!dev) {
        items.push({
          roomNumber: r.RoomNumber,
          startLiters: 0, endLiters: 0, usedLiters: 0,
          pricePerLiter, amount: 0, startAt: null, endAt: null
        });
        continue;
      }

      // 1) ใช้ค่าลิตร "สะสม" ต้น/ปลายรอบ
      const row = await qOne(`
      WITH first_last AS (
        SELECT
          COALESCE(
            (SELECT "TotalLiters" FROM "ElectricReading"
              WHERE "DeviceID"=$1 AND kind='water' AND "At"<$2
              ORDER BY "At" DESC LIMIT 1),
            (SELECT "TotalLiters" FROM "ElectricReading"
              WHERE "DeviceID"=$1 AND kind='water' AND "At">=$2 AND "At"<$3
              ORDER BY "At" ASC LIMIT 1)
          ) AS start_liters,
          (SELECT "TotalLiters" FROM "ElectricReading"
            WHERE "DeviceID"=$1 AND kind='water' AND "At"<$3
            ORDER BY "At" DESC LIMIT 1) AS end_liters,
          (SELECT "At" FROM "ElectricReading"
            WHERE "DeviceID"=$1 AND kind='water' AND "At"<$2
            ORDER BY "At" DESC LIMIT 1) AS start_at,
          (SELECT "At" FROM "ElectricReading"
            WHERE "DeviceID"=$1 AND kind='water' AND "At"<$3
            ORDER BY "At" DESC LIMIT 1) AS end_at
      ) SELECT * FROM first_last
    `, [dev, monthStart.toISOString(), monthEnd.toISOString()]);

      let sL = Number(row?.start_liters || 0);
      let eL = Number(row?.end_liters || 0);
      let usedLiters = Math.max(0, eL - sL);
      let startAt = row?.start_at || null;
      let endAt = row?.end_at || null;

      // 2) ถ้าไม่มีตัวเลขสะสม ใช้การอินทิเกรตจาก FlowLpm (ลิตร/นาที)
      if (usedLiters === 0) {
        const integ = await qOne(`
        WITH rows AS (
          SELECT "At","FlowLpm"
          FROM "ElectricReading"
          WHERE "DeviceID"=$1 AND kind='water'
            AND "At">=$2 AND "At"<$3
          ORDER BY "At" ASC
        ),
        seg AS (
          SELECT "At","FlowLpm",
                 LEAD("At") OVER (ORDER BY "At") AS next_at,
                 LEAD("FlowLpm") OVER (ORDER BY "At") AS next_flow
          FROM rows
        )
        SELECT
          MIN("At") AS start_at,
          MAX(COALESCE(next_at,"At")) AS end_at,
          COALESCE(SUM(((EXTRACT(EPOCH FROM (COALESCE(next_at,"At")-"At"))/60.0)
                        * (("FlowLpm"+COALESCE(next_flow,"FlowLpm"))/2.0))),0) AS used_liters
        FROM seg
      `, [dev, monthStart.toISOString(), monthEnd.toISOString()]);

        usedLiters = Number(integ?.used_liters || 0);
        // สำหรับความเข้าใจ: หากสะสมไม่ได้ ให้สื่อสาร start/end เป็น 0/used
        sL = 0; eL = usedLiters;
        startAt = integ?.start_at || startAt;
        endAt = integ?.end_at || endAt;
      }

      const amount = Number((usedLiters * pricePerLiter).toFixed(2)); // ✅ บาท/ลิตร
      items.push({
        roomNumber: r.RoomNumber,
        startLiters: sL,
        endLiters: eL,
        usedLiters,
        pricePerLiter,
        amount,
        startAt, endAt
      });
    }

    const totalLiters = items.reduce((a, b) => a + Number(b.usedLiters || 0), 0);
    const totalAmount = Number(items.reduce((a, b) => a + Number(b.amount || 0), 0).toFixed(2));

    res.json({
      month: ym,
      unit: { waterVolume: 'L', waterBilling: 'THB_per_L' },
      pricePerLiter,
      totalLiters,
      totalAmount,
      items
    });
  });



  // ===== ดึงค่าจาก Tuya ทั้งตึก (insert readings) =====
  router.post('/building/:buildingId/tuya/pull-electric', requireAuth, ensureBuildingId,  async (req, res) => {
    const CRON_SECRET = process.env.ELECTRIC_CRON_SECRET || '';
    const okFromCron = CRON_SECRET && (req.headers['x-cron-secret'] === CRON_SECRET);
    if (CRON_SECRET && !okFromCron) {
      return res.status(403).json({ ok: false, error: 'forbidden (cron secret mismatch)' });
    }

    // ---- ตั้งค่าเล็กน้อยเพื่อกัน timeouts 9s ----
    const TUYA_CONCURRENCY = Number(process.env.TUYA_CONCURRENCY || 3);
    const TUYA_PER_DEVICE_TIMEOUT_MS = Number(process.env.TUYA_PER_DEVICE_TIMEOUT_MS || 2500);

    function withTimeout(promise, ms) {
      return Promise.race([
        promise,
        new Promise((_, rej) => setTimeout(() => rej(new Error('TUYA_TIMEOUT')), ms)),
      ]);
    }

    async function runLimited(items, limit, worker) {
      const running = new Set();
      let i = 0;
      const results = [];

      async function kick() {
        while (i < items.length) {
          const idx = i++;
          const p = worker(items[idx])
            .then(r => { results[idx] = r; })
            .catch(e => { results[idx] = e; })
            .finally(() => running.delete(p));
          running.add(p);
          if (running.size >= limit) await Promise.race(running);
        }
      }

      await kick();
      await Promise.allSettled([...running]);
      return results;
    }

    const b = req.buildingId;
    const debug = String(req.query.debug || '') === '1';

    try {
      const devices = await qAny(`
      SELECT td."DeviceID", td."RoomNumber", td."Active", td.dp_map, td.device_kind
      FROM "TuyaDevice" AS td
      JOIN "Room" AS r
        ON r."RoomNumber" = td."RoomNumber" AND r."BuildingID" = td.building_id
      WHERE r."BuildingID" = $1 AND COALESCE(td."Active", FALSE) IS TRUE
      ORDER BY td."RoomNumber" ASC
    `, [b]);

      const rows = [];
      let inserted = 0;

      const normKey = s => String(s || '').toLowerCase().replace(/[\s_-]+/g, ' ').trim();
      const firstByKeys = (obj, keys) => {
        if (!obj) return undefined;
        const list = Array.isArray(keys) ? keys : [keys];
        for (const k of list) if (obj?.[k] != null) return obj[k];
        const dict = Object.fromEntries(Object.entries(obj).map(([k, v]) => [normKey(k), v]));
        for (const k of list) {
          const v = dict[normKey(k)];
          if (v != null) return v;
        }
        return undefined;
      };
      const numVal = v => {
        if (v == null) return 0;
        if (typeof v === 'number' && isFinite(v)) return v;
        const m = String(v).match(/-?\d+(?:\.\d+)?/);
        return m ? parseFloat(m[0]) : 0;
      };

      await runLimited(devices, TUYA_CONCURRENCY, async (d) => {
        try {
          const flat = await withTimeout(getDeviceStatus(d.DeviceID), TUYA_PER_DEVICE_TIMEOUT_MS);
          const now = new Date();

          const m = (typeof d.dp_map === 'string'
            ? (JSON.parse(d.dp_map || '{}') || {})
            : (d.dp_map || {}));

          const looksElectric =
            d.device_kind === 'electric' ||
            m.electric === true ||
            firstByKeys(flat, [m.power, 'cur_power', 'power', 'Power']) != null ||
            firstByKeys(flat, [m.voltage, 'cur_voltage', 'voltage', 'Voltage']) != null ||
            firstByKeys(flat, [m.current, 'cur_current', 'current', 'Current']) != null;

          if (looksElectric) {
            const pw = numVal(firstByKeys(flat, [m.power, 'cur_power', 'power', 'Power']));
            const vv = numVal(firstByKeys(flat, [m.voltage, 'cur_voltage', 'voltage', 'Voltage']));
            const cc = numVal(firstByKeys(flat, [m.current, 'cur_current', 'current', 'Current']));

            const energyKeys = Array.isArray(m.energy_keys) && m.energy_keys.length
              ? m.energy_keys
              : ['total_kwh', 'Total kWh', 'add_ele', 'energy', 'cur_energy', 'ele_total'];
            let kwhRaw;
            for (const k of energyKeys) {
              const v = firstByKeys(flat, [k]);
              if (v != null) { kwhRaw = numVal(v); break; }
            }
            let kwhVal = (Number.isFinite(kwhRaw) && kwhRaw > 0) ? kwhRaw : 0;

            const allowIntegrate = (m.integrate_power === true) || (pw > 0 && !kwhVal);
            if (allowIntegrate) {
              const prev = await qOne(`
          SELECT "EnergyKwh" AS kwh, "At" AS at
          FROM "ElectricReading"
          WHERE "DeviceID"=$1 AND (kind='electric' OR kind IS NULL)
          ORDER BY "At" DESC LIMIT 1
        `, [d.DeviceID]);

              const prevK = Number(prev?.kwh || 0);
              const prevAt = prev?.at ? new Date(prev.at) : null;
              let dtHours = 0;
              if (prevAt) {
                dtHours = Math.max(0, (now.getTime() - prevAt.getTime()) / 3600000);
                dtHours = Math.min(dtHours, 2);
              }
              const deltaKwh = (pw > 0 && dtHours > 0) ? (pw / 1000) * dtHours : 0;
              kwhVal = Number((prevK + deltaKwh).toFixed(6));
            }

            await qNone(`
        INSERT INTO "ElectricReading"
          ("RoomNumber","DeviceID","At","EnergyKwh","PowerW","VoltageV","CurrentA","raw",kind)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'electric')
      `, [d.RoomNumber, d.DeviceID, now.toISOString(), kwhVal, pw, vv, cc, debug ? JSON.stringify(flat) : null]);

            rows.push({ type: 'electric', room: d.RoomNumber, deviceId: d.DeviceID, kwh: kwhVal, powerW: pw, voltage: vv, current: cc });
            inserted++;
          }

          if (d.device_kind === 'water' || m.water === true) {
            const getVal = (obj, keys) => firstByKeys(obj, keys);
            const toNum = v => {
              if (v == null) return 0;
              if (typeof v === 'number' && isFinite(v)) return v;
              const m = String(v).match(/-?\d+(?:\.\d+)?/);
              return m ? parseFloat(m[0]) : 0;
            };

            const litersScale = Number(m?.liters_scale ?? 0.1);
            const onceScale = Number(m?.once_scale ?? 0.1);
            const flowScale = Number(m?.flow_scale ?? 0.1);
            const battScale = Number(m?.battery_scale ?? 1);

            const litersRaw = getVal(flat, m?.liters ?? ['water_use_data', 'total_use', 'Total Use']);
            const onceRaw = getVal(flat, m?.once ?? ['water_once', 'single_use', 'Single Use']);
            const flowRaw = getVal(flat, m?.flow ?? ['flow_velocity', 'flow_rate', 'Flow Rate']);
            const battRaw = getVal(flat, m?.battery_pct ?? ['voltage_current', 'power_supply_voltage', 'Battery']);

            const litersAcc = Number((toNum(litersRaw) * litersScale).toFixed(3));
            const onceLiters = Number((toNum(onceRaw) * onceScale).toFixed(3));
            const flowLpm = Number((toNum(flowRaw) * flowScale).toFixed(3));
            const vPct = Number((toNum(battRaw) * battScale).toFixed(2));

            const prev = await qOne(`
        SELECT "TotalLiters" AS liters
        FROM "ElectricReading"
        WHERE "DeviceID"=$1 AND kind='water'
        ORDER BY "At" DESC LIMIT 1
      `, [d.DeviceID]);
            const prevLiters = Number(prev?.liters || 0);

            let totalLiters = litersAcc > 0 ? litersAcc
              : (onceLiters > 0 ? Number((prevLiters + onceLiters).toFixed(3)) : prevLiters);

            if (litersAcc > 0 && prevLiters > 0 && litersAcc + 1e-6 < prevLiters && onceLiters > 0) {
              totalLiters = Number((prevLiters + onceLiters).toFixed(3));
            }

            await qNone(`
        INSERT INTO "ElectricReading"
          ("RoomNumber","DeviceID","At","TotalLiters","FlowLpm","VoltagePct","raw",kind)
        VALUES ($1,$2,$3,$4,$5,$6,$7,'water')
      `, [d.RoomNumber, d.DeviceID, now.toISOString(), totalLiters, flowLpm, vPct, debug ? JSON.stringify(flat) : null]);

            rows.push({ type: 'water', room: d.RoomNumber, deviceId: d.DeviceID, liters_total: totalLiters, liters_added: onceLiters, flowLpm, voltagePct: vPct });
            inserted++;
          }
        } catch (e) {
          rows.push({ room: d.RoomNumber, deviceId: d.DeviceID, error: String(e?.message || e) });
        }
      });


      return res.status(201).json({ ok: true, inserted, rows });
    } catch (err) {
      console.error('pull-electric failed:', err);
      return res.status(500).json({ ok: false, error: String(err?.message || err) });
    }
  });



  // ===== probe: สถานะดิบของอุปกรณ์ (ช่วยหา dp_map) =====
  router.get('/tuya/devices/:deviceId/status', requireAuth, async (req, res) => {
    try {
      const flat = await getDeviceStatus(req.params.deviceId);
      res.json({ ok: true, deviceId: req.params.deviceId, flat });
    } catch (e) {
      res.status(502).json({ ok: false, error: String(e?.message || e) });
    }
  });

  // (ตัวเลือก) toggle รีเลย์ในแต่ละห้อง
  router.post('/rooms/:roomId/relay', requireAuth, async (req, res) => {
    const room = req.params.roomId;
    const on = !!req.body.on;

    const row = await qOne(`
      SELECT "DeviceID", dp_map
      FROM "TuyaDevice"
      WHERE "RoomNumber" = $1
        AND COALESCE("Active", FALSE) IS TRUE
      ORDER BY id DESC
      LIMIT 1
    `, [room]);

    if (!row) return res.status(404).json({ error: 'Device not found' });

    const code = (row.dp_map && row.dp_map.relay && (row.dp_map.relay.code || row.dp_map.relay)) || 'switch_1';
    try {
      await sendDeviceCommand(row.DeviceID, code, on);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ ok: false, error: String(e?.message || e) });
    }
  });

  return router;
};
