// routes/meters.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // แปลงผลลัพธ์ให้อยู่ในรูปที่แอปอ่านได้ (ดู TenantMeter.fromJson ฝั่งแอป)
  const rowToPayload = (row) => ({
    id: row.id,                                // ตอนนี้ใช้ TenantID เป็น id ชั่วคราว
    deviceId: row.device_id || '',             // ถ้ายังไม่มีตารางอุปกรณ์ ปล่อยว่างไว้ได้
    name: row.room_no || null,                 // ให้ชื่อการ์ดเป็นเลขห้อง
    credit_kwh: Number(row.credit_kwh || 0),   // เครดิตไฟฟ้าจาก UnitBalance
    is_cut: !!row.is_cut,                      // ยังไม่มีสถานะตัดไฟจริง -> false ไปก่อน
    threshold_low_kwh: row.threshold_low_kwh || null,
    threshold_critical_kwh: row.threshold_critical_kwh || null,
  });

  // ========== SQL พื้นฐาน ==========
  // ดึง "มิเตอร์ของผู้เช่า" แบบง่าย: ผูกจาก Tenant -> Room -> UnitBalance (ElectricUnit)
  const SQL_BY_TENANT = `
    SELECT 
      t."TenantID"        AS id,
      t."RoomNumber"      AS room_no,
      COALESCE(ub."ElectricUnit", 0) AS credit_kwh,
      FALSE               AS is_cut,
      NULL::numeric       AS threshold_low_kwh,
      NULL::numeric       AS threshold_critical_kwh,
      NULL::text          AS device_id
    FROM "Tenant" t
    LEFT JOIN "UnitBalance" ub ON ub."TenantID" = t."TenantID"
    WHERE t."TenantID" = $1
  `;

  // ดึง "มิเตอร์ของห้อง" จากเลขห้อง
  const SQL_BY_ROOM = `
    SELECT 
      t."TenantID"        AS id,
      r."RoomNumber"      AS room_no,
      COALESCE(ub."ElectricUnit", 0) AS credit_kwh,
      FALSE               AS is_cut,
      NULL::numeric       AS threshold_low_kwh,
      NULL::numeric       AS threshold_critical_kwh,
      NULL::text          AS device_id
    FROM "Room" r
    LEFT JOIN "Tenant" t      ON t."RoomNumber" = r."RoomNumber"
    LEFT JOIN "UnitBalance" ub ON ub."TenantID" = t."TenantID"
    WHERE r."RoomNumber" = $1
  `;

  // 1) GET /tenant-meters/:tenantId  (แอปคุณเรียกอันนี้เป็นตัว fallback)
  router.get('/tenant-meters/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'invalid tenantId' });
    try {
      const rows = await db.any(SQL_BY_TENANT, [tenantId]);
      return res.json({ items: rows.map(rowToPayload) });
    } catch (e) {
      console.error('tenant-meters error', e);
      return res.status(500).json({ error: 'internal error' });
    }
  });

  // 2) GET /room-meters/:roomNumber
  router.get('/room-meters/:roomNumber', async (req, res) => {
    try {
      const rows = await db.any(SQL_BY_ROOM, [req.params.roomNumber]);
      return res.json({ items: rows.map(rowToPayload) });
    } catch (e) {
      console.error('room-meters error', e);
      return res.status(500).json({ error: 'internal error' });
    }
  });

  // 3) GET /meters?tenantId=... | ?roomNumber=...
  router.get('/meters', async (req, res) => {
    try {
      if (req.query.tenantId) {
        const tenantId = Number(req.query.tenantId);
        if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'invalid tenantId' });
        const rows = await db.any(SQL_BY_TENANT, [tenantId]);
        return res.json({ items: rows.map(rowToPayload) });
      }
      if (req.query.roomNumber) {
        const rows = await db.any(SQL_BY_ROOM, [req.query.roomNumber]);
        return res.json({ items: rows.map(rowToPayload) });
      }
      return res.status(400).json({ error: 'require tenantId or roomNumber' });
    } catch (e) {
      console.error('meters error', e);
      return res.status(500).json({ error: 'internal error' });
    }
  });

  // 4) GET /tenant/meters   (อนาคตถ้ามี auth ใส่ req.user.tenantId ได้)
  router.get('/tenant/meters', async (req, res) => {
    const tenantId = Number(req.user?.tenantId || req.query.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId required' });
    try {
      const rows = await db.any(SQL_BY_TENANT, [tenantId]);
      return res.json({ items: rows.map(rowToPayload) });
    } catch (e) {
      console.error('tenant/meters error', e);
      return res.status(500).json({ error: 'internal error' });
    }
  });

  return router;
};
