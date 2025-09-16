// routes/tenant.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /api/building/:id/tenant-count
router.get('/building/:id/tenant-count', async (req, res) => {
  const bId = Number(req.params.id);
  if (!Number.isInteger(bId) || bId <= 0) {
    return res.status(400).json({ error: 'invalid id' });
  }
  try {
    const row = await db.one(`
      SELECT COUNT(*)::int AS count
      FROM "Tenant" t
      JOIN "Room" r ON r."RoomNumber" = t."RoomNumber"
      WHERE r."BuildingID" = $1
        AND (t."Start" IS NULL OR t."Start" <= NOW())
        AND (t."End"   IS NULL OR t."End"   >  NOW())
    `, [bId]);
    res.json({ count: row.count });
  } catch (e) { res.status(500).json({ error: e.message }); }
});


  // GET /api/building/:buildingId/tenants
  router.get('/building/:buildingId/tenants', async (req, res) => {
    const buildingId = Number(req.params.buildingId);
    if (!Number.isInteger(buildingId) || buildingId <= 0) {
      return res.status(400).json({ error: 'buildingId required' });
    }
    try {
      const rows = await db.any(`
      SELECT
        t."TenantID",
        COALESCE(t."FirstName",'') || ' ' || COALESCE(t."LastName",'') AS "FullName",
        t."Phone",
        t."Email",
        r."RoomNumber",
        r."BuildingID",
        CASE
          WHEN lower(r."Status") IN ('vacant','ว่าง') THEN 'vacant'
          WHEN lower(r."Status") IN ('repair','ซ่อมบำรุง') THEN 'repair'
          ELSE 'occupied'
        END AS "Status"
      FROM "Tenant" t
      JOIN "Room" r ON t."RoomNumber" = r."RoomNumber"
      WHERE r."BuildingID" = $1
        AND (t."Start" IS NULL OR t."Start" <= NOW())
        AND (t."End"   IS NULL OR t."End"   >  NOW())
      ORDER BY "FullName" ASC
    `, [buildingId]);
      res.json(rows);
    } catch (err) {
      console.error('GET tenants error', err);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });


  return router;
};
