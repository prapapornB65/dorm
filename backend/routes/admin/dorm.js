const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /api/dorms - Fetch all dorm data
  router.get('/dorms', async (_req, res) => {
    try {
      const result = await db.any(`
        SELECT
          b."BuildingID"  AS id,
          b."BuildingName" AS dorm_name,
          o."FirstName"    AS owner_first_name,
          o."LastName"     AS owner_last_name,
          o."Phone"        AS owner_phone,
          b."Floors"       AS total_floors,
          b."Rooms"        AS total_rooms
        FROM public."Building" b
        LEFT JOIN public."Owner" o ON b."OwnerID" = o."OwnerID"
        ORDER BY b."BuildingID" ASC;
      `);

      const dormsData = result.map(row => ({
        id: row.id ? String(row.id) : '',
        dormName: row.dorm_name || 'ไม่ระบุชื่อหอพัก',
        ownerName: `${row.owner_first_name || ''} ${row.owner_last_name || ''}`.trim(),
        ownerPhone: row.owner_phone || 'N/A',
        registeredDate: 'N/A', // ปรับเพิ่มได้หากมีใน schema จริง
        totalFloors: row.total_floors != null ? String(row.total_floors) : 'N/A',
        totalRooms: row.total_rooms  != null ? String(row.total_rooms)  : 'N/A',
        status: 'ไม่ระบุสถานะ'
      }));

      res.json(dormsData);
    } catch (error) {
      console.error('❌ Error fetching dorms:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลหอพัก', details: error.message });
    }
  });

  return router;
};
