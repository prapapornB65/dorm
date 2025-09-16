// routes/billing.js
const express = require('express');

module.exports = (db) => {
    const router = express.Router();

    // routes/billing.js (ส่วนของ /bills)
    router.get('/building/:id/bills', async (req, res) => {
        const buildingId = Number(req.params.id);
        const month = (req.query.month || '').toString().slice(0, 7); // YYYY-MM
        if (!Number.isInteger(buildingId) || buildingId <= 0) {
            return res.status(400).json({ error: 'invalid building id' });
        }
        if (!/^\d{4}-\d{2}$/.test(month)) {
            return res.status(400).json({ error: 'month required as YYYY-MM' });
        }

        try {
            const rows = await db.any(`
      WITH pay AS (
        SELECT
          t."RoomNumber" AS "RoomNumber",
          CASE
            WHEN d."Year" IS NOT NULL AND d."Month" IS NOT NULL
              THEN to_char(make_date(d."Year", d."Month", 1), 'YYYY-MM')
            ELSE to_char(date_trunc('month', p."PaymentDate"), 'YYYY-MM')
          END AS ym,

          SUM(CASE WHEN lower(d."ItemType") IN ('rent','ค่าเช่า')
                   THEN COALESCE(d."Amount",0)::numeric ELSE 0 END) AS "RentAmount",
          MAX(CASE WHEN lower(d."ItemType") IN ('rent','ค่าเช่า')
                   THEN COALESCE(p."Status",'unpaid') END) AS "RentStatus",

          SUM(CASE WHEN lower(d."ItemType") IN ('electric','ไฟ','ค่าไฟ')
                   THEN COALESCE(d."Amount",0)::numeric ELSE 0 END) AS "ElectricAmount",
          MAX(CASE WHEN lower(d."ItemType") IN ('electric','ไฟ','ค่าไฟ')
                   THEN COALESCE(p."Status",'unpaid') END) AS "ElectricStatus",

          SUM(CASE WHEN lower(d."ItemType") IN ('water','น้ำ','ค่าน้ำ')
                   THEN COALESCE(d."Amount",0)::numeric ELSE 0 END) AS "WaterAmount",
          MAX(CASE WHEN lower(d."ItemType") IN ('water','น้ำ','ค่าน้ำ')
                   THEN COALESCE(p."Status",'unpaid') END) AS "WaterStatus"
        FROM "Payment" p
        LEFT JOIN "PaymentDetail" d ON d."PaymentID" = p."PaymentID"
        LEFT JOIN "Tenant" t        ON t."TenantID"   = p."TenantID"
        GROUP BY 1,2 -- (t.RoomNumber, ym)
      ),

      base_rent AS (
        SELECT r."RoomNumber", rt."PricePerMonth"::numeric AS "StdRent"
        FROM "Room" r
        LEFT JOIN "RoomType" rt ON rt."RoomTypeID" = r."RoomTypeID"
        WHERE r."BuildingID" = $1
      ),

      current_tenant AS (
        SELECT DISTINCT ON (t."RoomNumber")
               t."RoomNumber",
               COALESCE(t."FirstName",'') || ' ' || COALESCE(t."LastName",'') AS "TenantName"
        FROM "Tenant" t
        JOIN "Room" r ON r."RoomNumber" = t."RoomNumber"
        WHERE r."BuildingID" = $1
          AND (t."Start" IS NULL OR t."Start" <= NOW())
          AND (t."End"   IS NULL OR t."End"   >  NOW())
        ORDER BY t."RoomNumber", t."TenantID" DESC
      )

      SELECT
        r."RoomNumber",
        COALESCE(ct."TenantName",'') AS "TenantName",

        COALESCE(p."RentAmount",  br."StdRent", 0) AS "RentAmount",
        COALESCE(NULLIF(p."RentStatus", ''),  CASE WHEN br."StdRent" IS NULL THEN 'paid' ELSE 'unpaid' END) AS "RentStatus",

        COALESCE(p."ElectricAmount", 0) AS "ElectricAmount",
        COALESCE(NULLIF(p."ElectricStatus", ''), 'unpaid') AS "ElectricStatus",

        COALESCE(p."WaterAmount", 0) AS "WaterAmount",
        COALESCE(NULLIF(p."WaterStatus", ''), 'unpaid') AS "WaterStatus"

      FROM "Room" r
      LEFT JOIN pay p
             ON p."RoomNumber" = r."RoomNumber"
            AND p.ym = $2
      LEFT JOIN base_rent br
             ON br."RoomNumber" = r."RoomNumber"
      LEFT JOIN current_tenant ct
             ON ct."RoomNumber" = r."RoomNumber"
      WHERE r."BuildingID" = $1
      ORDER BY r."RoomNumber" ASC
    `, [buildingId, month]);

            res.json(rows);
        } catch (e) {
            console.error('GET /building/:id/bills error', e);
            res.status(500).json({ error: 'DB_ERROR' });
        }
    });


    router.get('/building/:id/bills-stats', async (req, res) => {
  const buildingId = Number(req.params.id);
  const month = (req.query.month || '').toString().slice(0,7);
  if (!Number.isInteger(buildingId) || buildingId <= 0) {
    return res.status(400).json({ error: 'invalid building id' });
  }
  if (!/^\d{4}-\d{2}$/.test(month)) {
    return res.status(400).json({ error: 'month required as YYYY-MM' });
  }

  try {
    const rows = await db.any(`
      WITH pay AS (
        SELECT
          t."RoomNumber" AS "RoomNumber",
          CASE
            WHEN d."Year" IS NOT NULL AND d."Month" IS NOT NULL
              THEN to_char(make_date(d."Year", d."Month", 1), 'YYYY-MM')
            ELSE to_char(date_trunc('month', p."PaymentDate"), 'YYYY-MM')
          END AS ym,

          SUM(CASE WHEN lower(d."ItemType") IN ('rent','ค่าเช่า')
                   THEN COALESCE(d."Amount",0)::numeric ELSE 0 END) AS "RentAmount",
          MAX(CASE WHEN lower(d."ItemType") IN ('rent','ค่าเช่า')
                   THEN COALESCE(p."Status",'unpaid') END) AS "RentStatus",

          SUM(CASE WHEN lower(d."ItemType") IN ('electric','ไฟ','ค่าไฟ')
                   THEN COALESCE(d."Amount",0)::numeric ELSE 0 END) AS "ElectricAmount",
          MAX(CASE WHEN lower(d."ItemType") IN ('electric','ไฟ','ค่าไฟ')
                   THEN COALESCE(p."Status",'unpaid') END) AS "ElectricStatus",

          SUM(CASE WHEN lower(d."ItemType") IN ('water','น้ำ','ค่าน้ำ')
                   THEN COALESCE(d."Amount",0)::numeric ELSE 0 END) AS "WaterAmount",
          MAX(CASE WHEN lower(d."ItemType") IN ('water','น้ำ','ค่าน้ำ')
                   THEN COALESCE(p."Status",'unpaid') END) AS "WaterStatus"
        FROM "Payment" p
        LEFT JOIN "PaymentDetail" d ON d."PaymentID" = p."PaymentID"
        LEFT JOIN "Tenant" t        ON t."TenantID"   = p."TenantID"
        GROUP BY 1,2
      ),
      base AS (
        SELECT r."RoomNumber", rt."PricePerMonth"::numeric AS "StdRent"
        FROM "Room" r LEFT JOIN "RoomType" rt ON rt."RoomTypeID" = r."RoomTypeID"
        WHERE r."BuildingID" = $1
      )

      SELECT
        COUNT(*) FILTER (WHERE lower(COALESCE(p."RentStatus",     CASE WHEN b."StdRent" IS NULL THEN 'paid' ELSE 'unpaid' END)) <> 'paid'
                         AND COALESCE(p."RentAmount", b."StdRent", 0) > 0) AS "dueRent",
        COUNT(*) FILTER (WHERE lower(COALESCE(p."ElectricStatus", 'unpaid')) <> 'paid'
                         AND COALESCE(p."ElectricAmount", 0) > 0) AS "dueElectric",
        COUNT(*) FILTER (WHERE lower(COALESCE(p."WaterStatus",    'unpaid')) <> 'paid'
                         AND COALESCE(p."WaterAmount", 0) > 0) AS "dueWater"
      FROM "Room" r
      LEFT JOIN pay  p ON p."RoomNumber" = r."RoomNumber" AND p.ym = $2
      LEFT JOIN base b ON b."RoomNumber" = r."RoomNumber"
      WHERE r."BuildingID" = $1
    `, [buildingId, month]);

    res.json(rows?.[0] || { dueRent: 0, dueElectric: 0, dueWater: 0 });
  } catch (e) {
    console.error('GET /building/:id/bills-stats error', e);
    res.status(500).json({ error: 'DB_ERROR' });
  }
});


    return router;
};
