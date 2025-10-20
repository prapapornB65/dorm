// routes/tenant/room.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /tenant-room/:tenantId
  router.get('/tenant-room/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const r = await db.oneOrNone(`SELECT "RoomNumber" FROM "Tenant" WHERE "TenantID"=$1`, [tenantId]);
      if (!r) return res.status(404).json({ error: 'ไม่พบ tenantId นี้' });
      res.json({ roomNumber: r.RoomNumber });
    } catch (e) {
      console.error('DB ERROR:', e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดฝั่งเซิร์ฟเวอร์' });
    }
  });
  // GET /room-detail/:RoomNumber
  router.get('/room-detail01/:RoomNumber', async (req, res) => {
    console.log('[ROOM-DETAIL v2] file=%s pid=%s at=%s Room=%s',
    __filename, process.pid, new Date().toISOString(), req.params.RoomNumber);
    const RoomNumber = req.params.RoomNumber;

    try {
      const room = await db.oneOrNone(`
      SELECT 
        r."RoomNumber",
        r."Address",
        r."Capacity",
        r."Status",
        rt."TypeName"       AS "RoomType",
        rt."PricePerMonth"  AS "Price",
        rt."Description"    AS "RoomTypeDesc",
        r."BuildingID",
        b."BuildingName",
        b."Address"         AS "BuildingAddress",
        b."QrCodeUrl",
        r."Size",

        /* ✅ ดึงรายการอุปกรณ์เป็น JSON array ของ string */
        COALESCE(
          (
            SELECT json_agg(e."EquipmentName" ORDER BY e."EquipmentName")
            FROM "RoomEquipment" re
            JOIN "Equipment" e ON e."EquipmentID" = re."EquipmentID"
            WHERE re."RoomNumber" = r."RoomNumber"
          ),
          '[]'::json
        ) AS "EquipmentList"
      FROM "Room" r
      LEFT JOIN "RoomType" rt ON r."RoomTypeID" = rt."RoomTypeID"
      LEFT JOIN "Building" b  ON r."BuildingID" = b."BuildingID"
      WHERE r."RoomNumber" = $1
      LIMIT 1
    `, [RoomNumber]);

      if (!room) return res.status(404).json({ error: 'ไม่พบห้องนี้' });

      // ล็อกดีบักให้เห็นชัด ๆ
      console.log('[ROOM-DETAIL] room =', RoomNumber, 'Size=', room.Size, 'EquipmentList len=', (room.EquipmentList || []).length);

      res.json(room);
    } catch (e) {
      console.error('❌ /room-detail error:', e);
      res.status(500).json({ error: e.message });
    }
  });


  // GET /tenant-room-detail/:tenantId
  router.get('/tenant-room-detail/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) {
      return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });
    }
    try {
      const row = await db.oneOrNone(`
      SELECT 
        t."TenantID", t."FirstName", t."LastName", t."Phone",
        t."RoomNumber",
        r."Status" AS room_status,
        b."BuildingName",
        b."QrCodeUrl",
        -- ✅ ใช้ SQL แปลงเป็น ISO 8601
        to_char(t."Start" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "StartISO",
        r."Size",
        rt."PricePerMonth" AS "PricePerMonth"
      FROM "Tenant" t
      LEFT JOIN "Room" r       ON t."RoomNumber" = r."RoomNumber"
      LEFT JOIN "Building" b   ON r."BuildingID" = b."BuildingID"
      LEFT JOIN "RoomType" rt  ON r."RoomTypeID" = rt."RoomTypeID"
      WHERE t."TenantID" = $1
    `, [tenantId]);

      if (!row) return res.status(404).json({ error: 'ไม่พบผู้เช่า' });

      // (โหลด repairs/equipments/symptomMap ตามของเดิมคุณ)
      const repairs = await db.any(`
      SELECT 
        "Equipment"   AS equipment, 
        "IssueDetail" AS issuedetail, 
        "Phone"       AS phone, 
        "RequestDate" AS requestdate, 
        "Status"      AS status
      FROM "RepairRequest"
      WHERE "TenantID" = $1
      ORDER BY "RequestDate" DESC
    `, [tenantId]);

      const equipments = await db.any(`SELECT "EquipmentName" FROM "Equipment" ORDER BY "EquipmentName"`);
      const symptomRaw = await db.any(`SELECT "EquipmentName","Symptom" FROM "SymptomMap"`);
      const symptomMap = {};
      symptomRaw.forEach(({ EquipmentName, Symptom }) => {
        if (!symptomMap[EquipmentName]) symptomMap[EquipmentName] = [];
        symptomMap[EquipmentName].push(Symptom);
      });

      res.json({
        tenant: {
          TenantID: row.TenantID,
          FirstName: row.FirstName,
          LastName: row.LastName,
          Phone: row.Phone,
          RoomNumber: row.RoomNumber,
          BuildingName: row.BuildingName,
          room_status: row.room_status,
          QrCodeUrl: row.QrCodeUrl,
          Start: row.StartISO || null,   // ✅ ใช้ค่าที่ SELECT มาจริง
          Size: row.Size,
        },
        price: row.PricePerMonth ?? null,
        maintenanceCost: null,
        repairs,
        equipments: equipments.map(e => e.EquipmentName),
        symptomMap
      });
    } catch (error) {
      console.error('❌ /tenant-room-detail:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลผู้เช่าและซ่อม' });
    }
  });


  // GET /contact-owner/:tenantId
  router.get('/contact-owner/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const owner = await db.oneOrNone(`
        SELECT 
          o."OwnerID", o."FirstName", o."LastName", o."Email", o."Phone", o."CitizenID",
          b."QrCodeUrl"
        FROM public."Owner" o
        JOIN public."Building" b ON o."OwnerID" = b."OwnerID"
        JOIN public."Room" r ON b."BuildingID" = r."BuildingID"
        JOIN public."Tenant" t ON r."RoomNumber" = t."RoomNumber"
        WHERE t."TenantID" = $1
        LIMIT 1
      `, [tenantId]);

      if (!owner) return res.status(404).json({ error: 'ไม่พบเจ้าของหอพัก' });
      owner.OwnerName = `${owner.FirstName} ${owner.LastName}`;
      res.json(owner);
    } catch (e) {
      console.error('❌ /contact-owner:', e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลเจ้าของหอพัก' });
    }
  });

  // GET /tenant-room-price/:tenantId
  router.get('/tenant-room-price/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const t = await db.oneOrNone(`SELECT "RoomNumber" FROM public."Tenant" WHERE "TenantID"=$1`, [tenantId]);
      if (!t) return res.status(404).json({ error: 'ไม่พบผู้เช่า' });

      const roomPrice = await db.oneOrNone(`
        SELECT r."RoomNumber", rt."PricePerMonth" AS price
        FROM public."Room" r
        JOIN public."RoomType" rt ON r."RoomTypeID"=rt."RoomTypeID"
        WHERE r."RoomNumber"=$1
      `, [t.RoomNumber]);

      if (!roomPrice) return res.status(404).json({ error: 'ไม่พบข้อมูลราคาห้อง' });
      res.json({ roomNumber: roomPrice.RoomNumber, price: roomPrice.price });
    } catch (e) {
      console.error('❌ /tenant-room-price:', e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงราคาค่าห้อง' });
    }
  });

  router.get('/room-images/:roomNumber', async (req, res) => {
    const roomNumber = req.params.roomNumber;
    try {
      const rows = await db.any(`
        SELECT "ImageURL"
        FROM "RoomImage"
        WHERE "RoomNumber" = $1
      `, [roomNumber]);

      // ไม่มีการ map ชื่อคีย์แปลก ๆ — ให้คง "ImageURL" ตามที่แอปอ่านอยู่
      res.json(rows);
    } catch (err) {
      console.error('❌ /room-images:', err);
      res.status(500).json({ error: 'Failed to fetch room images' });
    }
  });

  return router;
};
