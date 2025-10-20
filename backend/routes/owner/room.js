// routes/room.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();
  
  // ========================================
  router.get('/rooms/:buildingId', async (req, res) => {
    const buildingId = parseInt(req.params.buildingId, 10);
    if (!Number.isFinite(buildingId)) {
      return res.status(400).json({ error: 'invalid buildingId' });
    }
    try {
      const rows = await db.any(`
        SELECT
          r."RoomNumber"                     AS "roomNumber",
          COALESCE(r."Status",'UNKNOWN')     AS status,
          COALESCE(r."PricePerMonth",0)::float8 AS "pricePerMonth",
          r."BuildingID"                     AS "buildingId"
        FROM "Room" r
        WHERE r."BuildingID" = $1
        ORDER BY r."RoomNumber" ASC
      `, [buildingId]);

      res.json({ items: rows });
    } catch (e) {
      console.error('rooms list error:', e);
      res.status(500).json({ error: 'SERVER_ERROR' });
    }
  });

  // ========================================
  // NEW: GET รายละเอียดห้อง (สำหรับ RoomSettingsPage)
  // GET /api/room-detail/:roomNumber
  // ========================================
  router.get('/room-detail/:roomNumber', async (req, res) => {
    const roomNumber = req.params.roomNumber;

    if (!roomNumber || roomNumber.trim() === '') {
      return res.status(400).json({ error: 'roomNumber is required' });
    }

    try {
      const room = await db.oneOrNone(`
        SELECT 
          r."RoomNumber",
          r."Address",
          r."Capacity",
          r."Size",
          r."Status",
          r."BuildingID",
          r."RoomTypeID",
          r."PricePerMonth",
          rt."TypeName" AS "RoomType"
        FROM "Room" r
        LEFT JOIN "RoomType" rt ON rt."RoomTypeID" = r."RoomTypeID"
        WHERE r."RoomNumber" = $1
      `, [roomNumber]);

      if (!room) {
        return res.status(404).json({ error: 'Room not found' });
      }

      res.json(room);
    } catch (e) {
      console.error('GET room-detail error:', e);
      res.status(500).json({ error: 'SERVER_ERROR' });
    }
  });

  // ========================================
  // NEW: UPDATE ข้อมูลห้อง (สำหรับ RoomSettingsPage)
  // PUT /api/room-update/:roomNumber
  // ========================================
  router.put('/room-update/:roomNumber',  async (req, res) => {
    const roomNumber = req.params.roomNumber;
    const { Address, Capacity, Size, Status } = req.body || {};

    if (!roomNumber || roomNumber.trim() === '') {
      return res.status(400).json({ error: 'roomNumber is required' });
    }

    try {
      // ตรวจสอบว่าห้องมีอยู่จริง
      const exists = await db.oneOrNone(
        'SELECT "RoomNumber" FROM "Room" WHERE "RoomNumber" = $1',
        [roomNumber]
      );

      if (!exists) {
        return res.status(404).json({ error: 'Room not found' });
      }

      // อัปเดตข้อมูล
      await db.none(`
        UPDATE "Room"
        SET 
          "Address" = COALESCE($2, "Address"),
          "Capacity" = COALESCE($3, "Capacity"),
          "Size" = COALESCE($4, "Size"),
          "Status" = COALESCE($5, "Status")
        WHERE "RoomNumber" = $1
      `, [
        roomNumber,
        Address || null,
        Capacity != null ? parseInt(Capacity) : null,
        Size != null ? parseFloat(Size) : null,
        Status || null
      ]);

      res.json({
        success: true,
        message: 'Room updated successfully',
        roomNumber
      });
    } catch (e) {
      console.error('PUT room-update error:', e);
      res.status(500).json({ error: 'SERVER_ERROR' });
    }
  });

  // ========================================
  // NEW: DELETE ห้อง (สำหรับ RoomListPage)
  // DELETE /api/rooms/:roomNumber
  // ========================================
  router.delete('/rooms/:roomNumber',  async (req, res) => {
    const roomNumber = decodeURIComponent(req.params.roomNumber);

    if (!roomNumber || roomNumber.trim() === '') {
      return res.status(400).json({ error: 'roomNumber is required' });
    }

    try {
      await db.tx(async t => {
        // ตรวจสอบว่าห้องมีผู้เช่าอยู่หรือไม่
        const tenant = await t.oneOrNone(`
          SELECT "TenantID" 
          FROM "Tenant" 
          WHERE "RoomNumber" = $1 
            AND ("End" IS NULL OR "End" > NOW())
        `, [roomNumber]);

        if (tenant) {
          throw new Error('ROOM_OCCUPIED');
        }

        // ลบข้อมูลที่เกี่ยวข้อง
        await t.none('DELETE FROM "RoomEquipment" WHERE "RoomNumber" = $1', [roomNumber]);
        await t.none('DELETE FROM "RoomImage" WHERE "RoomNumber" = $1', [roomNumber]);

        // ลบห้อง
        const result = await t.result(
          'DELETE FROM "Room" WHERE "RoomNumber" = $1',
          [roomNumber]
        );

        if (result.rowCount === 0) {
          throw new Error('ROOM_NOT_FOUND');
        }
      });

      res.status(200).json({
        success: true,
        message: 'Room deleted successfully'
      });
    } catch (e) {
      console.error('DELETE room error:', e);

      if (e.message === 'ROOM_OCCUPIED') {
        return res.status(400).json({
          error: 'ไม่สามารถลบห้องที่มีผู้เช่าอยู่ได้'
        });
      }
      if (e.message === 'ROOM_NOT_FOUND') {
        return res.status(404).json({ error: 'ไม่พบห้องที่ต้องการลบ' });
      }

      res.status(500).json({ error: 'SERVER_ERROR' });
    }
  });

  // ========================================
  // NEW: GET รูปภาพห้อง (สำหรับ RoomImagesPage & RoomSettingsPage)
  // GET /api/room-images/:roomNumber
  // ========================================
  router.get('/room-images/:roomNumber', async (req, res) => {
    const roomNumber = req.params.roomNumber;

    if (!roomNumber || roomNumber.trim() === '') {
      return res.status(400).json({ error: 'roomNumber is required' });
    }

    try {
      const images = await db.any(`
        SELECT 
          "ImageID",
          "RoomNumber",
          "ImageURL",
          "UploadedAt"
        FROM "RoomImage"
        WHERE "RoomNumber" = $1
        ORDER BY "UploadedAt" DESC
      `, [roomNumber]);

      // ส่งกลับเป็น array ของ object พร้อม key ที่ Flutter ต้องการ
      res.json(images);
    } catch (e) {
      console.error('GET room-images error:', e);
      res.status(500).json({ error: 'SERVER_ERROR' });
    }
  });

  return router;
};