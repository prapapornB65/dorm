// routes/tenant/room.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /api/tenant-room/:tenantId
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

  // GET /api/room-detail/:RoomNumber
  router.get('/room-detail/:RoomNumber', async (req, res) => {
    const RoomNumber = req.params.RoomNumber;
    try {
      const room = await db.oneOrNone(`
        SELECT 
          r."RoomNumber",
          r."Address",
          r."Capacity",
          r."Status",
          rt."TypeName" AS "RoomType",
          rt."PricePerMonth" AS "Price",
          rt."Description" AS "RoomTypeDesc",
          r."BuildingID",
          b."BuildingName",
          b."Address" AS "BuildingAddress",
          b."QrCodeUrl",
          t."FirstName",
          t."LastName",
          t."Start",
          r."Size"
        FROM public."Room" r
        LEFT JOIN public."RoomType" rt ON r."RoomTypeID" = rt."RoomTypeID"
        LEFT JOIN public."Building" b ON r."BuildingID" = b."BuildingID"
        LEFT JOIN public."Tenant" t ON t."RoomNumber" = r."RoomNumber"
        WHERE r."RoomNumber" = $1
      `, [RoomNumber]);

      if (!room) return res.status(404).json({ error: 'ไม่พบห้องนี้' });

      const equipments = await db.any(`
        SELECT e."EquipmentName"
        FROM public."RoomEquipment" re
        JOIN public."Equipment" e ON re."EquipmentID" = e."EquipmentID"
        WHERE re."RoomNumber" = $1
        ORDER BY e."EquipmentName"
      `, [RoomNumber]);

      room.EquipmentList = equipments.map(e => e.EquipmentName);
      res.json(room);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: e.message });
    }
  });

  router.get('/tenant-room-detail/:tenantId', async (req, res) => {
    const tenantId = parseInt(req.params.tenantId);
    try {
      const tenant = await db.oneOrNone(`
        SELECT 
          t."TenantID", t."FirstName", t."LastName", t."Phone",
          t."RoomNumber",
          r."Status" AS room_status,
          b."BuildingName",
          b."QrCodeUrl",
          t."Start",
          r."Size"
        FROM "Tenant" t
        LEFT JOIN "Room" r ON t."RoomNumber" = r."RoomNumber"
        LEFT JOIN "Building" b ON r."BuildingID" = b."BuildingID"
        WHERE t."TenantID" = $1
      `, [tenantId]);

      if (!tenant) return res.status(404).json({ error: 'ไม่พบผู้เช่า' });

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

      // ✅ สำคัญ: โครงสร้าง field ที่ Flutter อ่านใน TenantRoomOverview.fromJson()
      res.json({
        tenant: {
          TenantID: tenant.TenantID,
          FirstName: tenant.FirstName,
          LastName: tenant.LastName,
          Phone: tenant.Phone,
          RoomNumber: tenant.RoomNumber,
          BuildingName: tenant.BuildingName,
          room_status: tenant.room_status,
          QrCodeUrl: tenant.QrCodeUrl,
          Start: tenant.Start,
          Size: tenant.Size,
          // ไม่จำเป็นต้องส่ง price/maintenanceCost ก็ได้ (Flutter handle null)
        },
        repairs,
        equipments: equipments.map(e => e.EquipmentName),
        symptomMap
      });
    } catch (error) {
      console.error('❌ /tenant-room-detail:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลผู้เช่าและซ่อม' });
    }
  });

  // GET /api/contact-owner/:tenantId
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
      console.error('❌ /api/contact-owner:', e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลเจ้าของหอพัก' });
    }
  });

  // GET /api/tenant-room-price/:tenantId
  router.get('/api/tenant-room-price/:tenantId', async (req, res) => {
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
      console.error('❌ /api/tenant-room-price:', e);
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
