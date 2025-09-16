const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET OwnerID by FirebaseUID
  router.get('/owner-id-by-uid/:firebaseUID', async (req, res) => {
    const { firebaseUID } = req.params;
    try {
      const owner = await db.oneOrNone(
        'SELECT "OwnerID" FROM "Owner" WHERE "FirebaseUID" = $1',
        [firebaseUID]
      );
      if (!owner) return res.status(404).json({ error: 'ไม่พบ Owner ที่ตรงกับ UID นี้' });
      res.json(owner);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  // GET /owners - เจ้าของทั้งหมด
  router.get('/owners', async (req, res) => {
    try {
      const result = await db.any(`
        SELECT 
          o."OwnerID" as id, 
          o."FirstName", 
          o."LastName", 
          o."Email", 
          o."Phone", 
          o."CitizenID",
          o."StartDate",
          o."EndDate",
          b."BuildingName"
        FROM public."Owner" o
        LEFT JOIN public."Building" b ON b."OwnerID" = o."OwnerID"
        ORDER BY o."OwnerID" ASC;
      `);

      const ownersData = result.map(row => ({
        id: row.id.toString(),
        name: `${row.FirstName || ''} ${row.LastName || ''}`.trim(),
        phone: row.Phone || 'N/A',
        email: row.Email || 'N/A',
        dorm: row.BuildingName ? `หอพัก: ${row.BuildingName}` : 'ไม่ระบุหอพัก',
        date: row.StartDate && row.EndDate
          ? `${row.StartDate} - ${row.EndDate}`
          : 'N/A',
        status: 'ใช้งานอยู่'
      }));

      res.json(ownersData);
    } catch (error) {
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลเจ้าของหอพัก', details: error.message });
    }
  });

  // GET owner info by email
  router.get('/owner-info', async (req, res) => {
    const email = req.query.email;
    if (!email) return res.status(400).json({ error: "Missing email parameter" });

    try {
      const owner = await db.any('SELECT * FROM "Owner" WHERE "Email" = $1', [email]);
      if (owner.length === 0) return res.status(404).json({ error: "Owner not found" });
      res.json(owner[0]);
    } catch (error) {
      res.status(500).json({ error: "Internal server error" });
    }
  });

  return router;
};
