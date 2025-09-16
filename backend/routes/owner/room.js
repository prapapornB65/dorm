const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

module.exports = (db) => {
  const router = express.Router();

  /* ----------------------------------------------------
   * 1) ห้อง “ทุกตึก” (เดิม)
   *    GET /api/rooms
   * ---------------------------------------------------- */
  router.get('/rooms', async (_req, res) => {
    try {
      const rows = await db.any(`
        SELECT 
          r."RoomNumber", r."Address", r."Capacity", r."Status",
          rt."TypeName" AS "RoomType", rt."PricePerMonth" AS "Price",
          b."BuildingName", r."Size", r."BuildingID"
        FROM "Room" r
        LEFT JOIN "RoomType" rt ON r."RoomTypeID" = rt."RoomTypeID"
        LEFT JOIN "Building"  b  ON r."BuildingID"  = b."BuildingID"
        ORDER BY r."RoomNumber" ASC
      `);
      res.json(rows);
    } catch (err) {
      console.error('GET /rooms error:', err);
      res.status(500).json({ error: err.message });
    }
  });

  /* ----------------------------------------------------
   * 2) ห้อง “ตามตึก”
   *    GET /api/rooms/:buildingId
   *    (ตอบเป็น array ตรง ๆ ให้เข้ากับ OwnerDashboard ที่ parse เป็น list)
   * ---------------------------------------------------- */
  router.get('/rooms/:buildingId', async (req, res) => {
    const buildingId = Number(req.params.buildingId);
    if (!buildingId) return res.status(400).json({ error: 'invalid buildingId' });

    console.time(`GET /rooms/${buildingId}`);
    try {
      const rows = await db.any(
        `
        SELECT
          r."RoomNumber"                            AS "roomNumber",
          r."BuildingID"                            AS "buildingId",
          r."Status"                                AS "status",
          r."Size"                                  AS "size",
          r."Capacity"                              AS "capacity",
          rt."TypeName"                             AS "roomType",
          rt."PricePerMonth"                        AS "price",
          td."DeviceID"                             AS "deviceId",
          COALESCE(er."EnergyKwh",0)                AS "EnergyKwh",
          COALESCE(er."EnergyKwh",0)                AS "electric",   -- เผื่อโค้ดฝั่ง UI ใช้ key 'electric'
          COALESCE(er."PowerW",0)                   AS "powerW",
          er."At"                            AS "At",
          NULL                                      AS "tenant",     -- เว้น field ให้ UI ไม่พัง
          FALSE                                     AS "isOverdue",
          0.0                                       AS "water"
        FROM "Room" r
        LEFT JOIN "RoomType" rt
          ON rt."RoomTypeID" = r."RoomTypeID"
        LEFT JOIN "TuyaDevice" td
          ON td."RoomNumber" = r."RoomNumber" AND td."Active" = TRUE
        LEFT JOIN LATERAL (
          SELECT e."EnergyKwh", e."PowerW", e."At"
          FROM "ElectricReading" e
          WHERE e."RoomNumber" = r."RoomNumber"
          ORDER BY e."At" DESC
          LIMIT 1
        ) er ON TRUE
        WHERE r."BuildingID" = $1
        ORDER BY r."RoomNumber" ASC
        `,
        [buildingId]
      );

      res.json(rows); // 👈 ส่ง array ตรง ๆ
    } catch (err) {
      console.error(`GET /rooms/${buildingId} error:`, err);
      res.status(500).json({ error: err.message });
    } finally {
      console.timeEnd(`GET /rooms/${buildingId}`);
    }
  });

  /* ----------------------------------------------------
   * (ทางเลือก) 2.1) ยอดรวมผู้เช่าปัจจุบันในตึกเดียว
   *    GET /api/building/:id/tenant-count
   * ---------------------------------------------------- */
  router.get('/building/:id/tenant-count', async (req, res) => {
    const bId = Number(req.params.id);
    try {
      const row = await db.one(`
        SELECT COUNT(*)::int AS count
        FROM "Tenant" t
        JOIN "Room" r ON r."RoomNumber" = t."RoomNumber"
        WHERE r."BuildingID" = $1
          AND (t."End" IS NULL OR t."End" > NOW())
      `, [bId]);
      res.json({ count: row.count });
    } catch (e) {
      console.error('GET /building/:id/tenant-count error:', e);
      res.status(500).json({ error: e.message });
    }
  });

  /* ----------------------------------------------------
   * 3) อัปโหลดรูปห้อง  (ใช้โฟลเดอร์ backend/uploads)
   *    POST /api/room-images   (field = image)
   * ---------------------------------------------------- */
  const uploadDir = path.join(__dirname, '..', '..', 'uploads'); // -> backend/uploads
  fs.mkdirSync(uploadDir, { recursive: true });

  const storage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, uploadDir),
    filename: (_req, file, cb) => {
      const unique = Date.now() + '-' + Math.round(Math.random() * 1e9);
      cb(null, `room-${unique}${path.extname(file.originalname)}`);
    },
  });
  const upload = multer({ storage });

  router.post('/room-images', upload.single('image'), async (req, res) => {
    const { RoomNumber, BuildingID } = req.body;
    const imageFile = req.file;

    if (!imageFile) return res.status(400).json({ error: 'No image uploaded' });
    if (!RoomNumber || !BuildingID) {
      return res.status(400).json({ error: 'RoomNumber and BuildingID required' });
    }

    // base URL แบบยืดหยุ่น
    const base =
      process.env.PUBLIC_BASE_URL /* เช่น http://192.168.1.107:3000 */
      || `${req.protocol}://${req.get('host')}`;

    const imageUrl = `${base}/uploads/${imageFile.filename}`;

    try {
      await db.none(`
        INSERT INTO "RoomImage"("RoomNumber","BuildingID","ImageURL")
        VALUES ($1,$2,$3)
      `, [RoomNumber, BuildingID, imageUrl]);

      res.json({ message: 'Upload successful', imageUrl });
    } catch (err) {
      console.error('POST /room-images error:', err);
      res.status(500).json({ error: 'Upload failed' });
    }
  });

  /* ----------------------------------------------------
   * 4) ดูรูปของห้อง
   *    GET /api/room-images/:roomNumber
   * ---------------------------------------------------- */
  router.get('/room-images/:roomNumber', async (req, res) => {
    const roomNumber = req.params.roomNumber;
    try {
      const images = await db.any(`
        SELECT "ImageID","BuildingID","ImageURL","Description",
               -- ⚠️ ปรับชื่อคอลัมน์ให้ตรงกับจริงใน DB (CreateDate/CreatedAt?)
               COALESCE("Createdat", NOW()) AS "Createdat",
               "RoomNumber"
        FROM "RoomImage"
        WHERE "RoomNumber" = $1
        ORDER BY "ImageID" DESC
      `, [roomNumber]);
      res.json(images);
    } catch (err) {
      console.error('GET /room-images error:', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // รายละเอียดห้อง
router.get('/room-detail/:roomNumber', async (req, res) => {
  const rn = req.params.roomNumber;
  try {
    const row = await db.oneOrNone(`
      SELECT r."RoomNumber", r."Address", r."Capacity", r."Size", r."Status",
             r."BuildingID", b."BuildingName",
             r."RoomTypeID", rt."TypeName", rt."PricePerMonth"
      FROM "Room" r
      LEFT JOIN "Building"  b  ON b."BuildingID"  = r."BuildingID"
      LEFT JOIN "RoomType" rt ON rt."RoomTypeID" = r."RoomTypeID"
      WHERE r."RoomNumber" = $1
    `, [rn]);
    if (!row) return res.status(404).json({ error: 'not found' });
    res.json(row);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// อัปเดตห้อง
router.put('/room-update/:roomNumber', async (req, res) => {
  const rn = req.params.roomNumber;
  const { Address, Capacity, Size, Status } = req.body || {};
  try {
    await db.none(`
      UPDATE "Room"
      SET "Address"=$1, "Capacity"=$2, "Size"=$3, "Status"=$4
      WHERE "RoomNumber"=$5
    `, [Address, Capacity, Size, Status, rn]);
    res.json({ message: 'updated' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

  return router;
};



