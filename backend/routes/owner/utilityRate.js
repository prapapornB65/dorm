// routes/owner/utilityRate.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // ---------- 1) GET: อัตราค่าน้ำ/ไฟ ล่าสุดของตึก ----------
  // GET /api/building/:buildingId/utility-rate
  router.get('/building/:buildingId/utility-rate', async (req, res) => {
    const buildingId = Number(req.params.buildingId);
    try {
      const row = await db.oneOrNone(
        `
        SELECT "ElectricUnitPrice","WaterUnitPrice","EffectiveDate"
        FROM "UtilityRate"
        WHERE "BuildingID"=$1
        ORDER BY "EffectiveDate" DESC
        LIMIT 1
      `,
        [buildingId]
      );

      if (!row) {
        return res.json({
          electricUnitPrice: 0,
          waterUnitPrice: 0,
          effectiveDate: null,
        });
      }
      res.json({
        electricUnitPrice: Number(row.ElectricUnitPrice) || 0,
        waterUnitPrice: Number(row.WaterUnitPrice) || 0,
        effectiveDate: row.EffectiveDate,
      });
    } catch (e) {
      console.error('GET utility-rate error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ---------- 2) PUT: บันทึกอัตราค่าน้ำ/ไฟ (ตรงกับแอป Flutter) ----------
  // PUT /api/building/:buildingId/utility-rate
  // body รองรับทั้ง {electricPrice, waterPrice} หรือ {electricUnitPrice, waterUnitPrice}
  router.put('/building/:buildingId/utility-rate', express.json(), async (req, res) => {
    const buildingId = Number(req.params.buildingId);
    const ownerId = req.body.ownerId ?? null;

    const e =
      Number(req.body.electricPrice ?? req.body.electricUnitPrice ?? 0) || 0;
    const w = Number(req.body.waterPrice ?? req.body.waterUnitPrice ?? 0) || 0;
    const eff = (req.body.effectiveDate || new Date().toISOString().slice(0, 10));

    if (!buildingId) return res.status(400).json({ error: 'buildingId required' });

    try {
      const row = await db.one(
        `
        INSERT INTO "UtilityRate"
          ("WaterUnitPrice","ElectricUnitPrice","EffectiveDate","OwnerID","BuildingID")
        VALUES ($1,$2,$3,$4,$5)
        RETURNING "RateID","WaterUnitPrice","ElectricUnitPrice","EffectiveDate","OwnerID","BuildingID"
      `,
        [w, e, eff, ownerId, buildingId]
      );

      res.json({
        rateId: row.RateID,
        waterUnitPrice: Number(row.WaterUnitPrice) || 0,
        electricUnitPrice: Number(row.ElectricUnitPrice) || 0,
        effectiveDate: row.EffectiveDate,
        ownerId: row.OwnerID,
        buildingId: row.BuildingID,
      });
    } catch (e) {
      console.error('PUT utility-rate error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // (คง route เดิมไว้เพื่อ backward-compat ถ้ายังมี client เก่าเรียกใช้)
  // PUT /api/owner/utilities/rate
  router.put('/utilities/rate', express.json(), async (req, res) => {
    const { ownerId, buildingId, electricUnitPrice, waterUnitPrice, effectiveDate } = req.body || {};
    if (!ownerId || !buildingId) {
      return res.status(400).json({ error: 'ownerId and buildingId required' });
    }
    const eff = effectiveDate || new Date().toISOString().slice(0, 10);

    try {
      const row = await db.one(
        `
        INSERT INTO "UtilityRate"
          ("WaterUnitPrice","ElectricUnitPrice","EffectiveDate","OwnerID","BuildingID")
        VALUES ($1,$2,$3,$4,$5)
        RETURNING "RateID","WaterUnitPrice","ElectricUnitPrice","EffectiveDate","OwnerID","BuildingID"
      `,
        [Number(waterUnitPrice) || 0, Number(electricUnitPrice) || 0, eff, ownerId, buildingId]
      );
      res.json(row);
    } catch (e) {
      console.error('PUT utilities rate error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ---------- 3) GET: ค่าไฟรายห้อง (มีหน่วยต้นเดือน/ปลายเดือน) ----------
  // GET /api/building/:buildingId/electric/charges?month=YYYY-MM
  router.get('/building/:buildingId/electric/charges', async (req, res) => {
    try {
      const buildingId = Number(req.params.buildingId);
      const month = (req.query.month || '').trim(); // YYYY-MM

      // เดือนที่ต้องการ (หรือเดือนปัจจุบัน)
      const now = new Date();
      const [yy, mm] = month ? month.split('-').map(Number) : [now.getFullYear(), now.getMonth() + 1];

      // ทำเป็นสตริงเพื่อกัน timezone edge cases
      const mm2 = String(mm).padStart(2, '0');
      const monthStart = `${yy}-${mm2}-01`;
      const nextY = mm === 12 ? yy + 1 : yy;
      const nextM = mm === 12 ? 1 : mm + 1;
      const monthEnd = `${nextY}-${String(nextM).padStart(2, '0')}-01`;

      // เรตราคา/หน่วย (ใช้เฉพาะ ElectricUnitPrice)
      const rateRow = await db.oneOrNone(
        `
        SELECT "ElectricUnitPrice" AS rate
        FROM "UtilityRate"
        WHERE "BuildingID"=$1
        ORDER BY "EffectiveDate" DESC
        LIMIT 1
      `,
        [buildingId]
      );
      const rate = Number(rateRow?.rate || 0);

      // หา reading ต้นเดือน/ปลายเดือน
      const rows = await db.any(
        `
      SELECT
        r."RoomNumber"                                  AS "roomNumber",
        COALESCE(s_pre."EnergyKwh", s_post."EnergyKwh") AS "startKwh",
        COALESCE(s_pre."At",       s_post."At")         AS "startAt",
        e_pre."EnergyKwh"                                AS "endKwh",
        e_pre."At"                                       AS "endAt"
      FROM "Room" r
      -- ก่อนต้นเดือน: รายการล่าสุดที่ < monthStart
      LEFT JOIN LATERAL (
        SELECT er."EnergyKwh", er."At"
        FROM "ElectricReading" er
        WHERE er."RoomNumber" = r."RoomNumber" AND er."At" < $2::timestamptz
        ORDER BY er."At" DESC
        LIMIT 1
      ) s_pre ON TRUE
      -- รายการแรกของเดือน (ถ้าไม่มีก่อนต้นเดือนให้ใช้ตัวนี้แทน)
      LEFT JOIN LATERAL (
        SELECT er."EnergyKwh", er."At"
        FROM "ElectricReading" er
        WHERE er."RoomNumber" = r."RoomNumber"
          AND er."At" >= $2::timestamptz AND er."At" < $3::timestamptz
        ORDER BY er."At" ASC
        LIMIT 1
      ) s_post ON TRUE
      -- ปลายเดือน: รายการล่าสุดที่ < monthEnd
      LEFT JOIN LATERAL (
        SELECT er."EnergyKwh", er."At"
        FROM "ElectricReading" er
        WHERE er."RoomNumber" = r."RoomNumber" AND er."At" < $3::timestamptz
        ORDER BY er."At" DESC
        LIMIT 1
      ) e_pre ON TRUE
      WHERE r."BuildingID" = $1
      ORDER BY r."RoomNumber" ASC
    `,
        [buildingId, monthStart, monthEnd]
      );

      const items = rows.map((r) => {
        const start = Number(r.startKwh || 0);
        const end = Number(r.endKwh || 0);
        const kwh = Math.max(end - start, 0);
        const amount = +(kwh * rate).toFixed(2);
        return {
          roomNumber: r.roomNumber,
          startKwh: start,
          endKwh: end,
          kwh,
          pricePerUnit: rate,
          amount,
          startAt: r.startAt,
          endAt: r.endAt,
        };
      });

      const totalKwh = items.reduce((s, x) => s + x.kwh, 0);
      const totalAmount = +items.reduce((s, x) => s + x.amount, 0).toFixed(2);

      res.json({
        month: `${yy}-${mm2}`,
        rate,
        totalKwh,
        totalAmount,
        items,
      });
    } catch (err) {
      console.error('GET electric charges error', err);
      res.status(500).json({ error: 'INTERNAL_ERROR' });
    }
  });

  return router;
};
