// routes/tenant/usageHistory.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /api/utility-rate/:tenantId
  router.get('/utility-rate/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const rate = await db.oneOrNone(`
        SELECT ur."WaterUnitPrice", ur."ElectricUnitPrice", b."BuildingName"
        FROM public."UtilityRate" ur
        JOIN public."Building" b ON ur."BuildingID" = b."BuildingID"
        JOIN public."Tenant" t ON t."RoomNumber" IN (
          SELECT r."RoomNumber" FROM public."Room" r WHERE r."BuildingID" = b."BuildingID"
        )
        WHERE t."TenantID" = $1
        ORDER BY ur."EffectiveDate" DESC
        LIMIT 1
      `, [tenantId]);

      if (!rate) return res.status(404).json({ error: 'ไม่พบเรทราคา' });
      res.json(rate);
    } catch (e) {
      console.error('❌ /api/utility-rate:', e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงเรทราคา' });
    }
  });

  // GET /api/utility-usage/:tenantId (ล่าสุด 1 รายการ)
  router.get('/utility-usage/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const rows = await db.any(`
        SELECT "UsageID","WaterUsage","ElectricUsage","UsageDateTime","Balance","TenantID","RoomNumber"
        FROM public."UsageLog" WHERE "TenantID"=$1
        ORDER BY "UsageDateTime" DESC LIMIT 1
      `, [tenantId]);

      if (rows.length === 0) return res.status(404).json({ error: 'ไม่พบข้อมูลการใช้งาน' });
      res.json(rows[0]);
    } catch (e) {
      console.error('❌ /api/utility-usage:', e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลการใช้งาน' });
    }
  });

  // GET /api/notifications/:tenantId
  router.get('/notifications/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const noti = await db.any(`
        SELECT "NotificationID","Title","Message","IsRead","CreatedAt"
        FROM "Notification"
        WHERE "TenantID"=$1
        ORDER BY "CreatedAt" DESC
        LIMIT 10
      `, [tenantId]);

      res.json(noti);
    } catch (e) {
      console.error('Error fetching notifications:', e);
      res.status(500).json({ error: 'ไม่สามารถดึงแจ้งเตือนได้' });
    }
  });

  // GET /api/combined-history/:tenantId
  router.get('/combined-history/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const utilityPurchases = await db.any(`
        SELECT * FROM public."UtilityPurchase" WHERE "TenantID"=$1 ORDER BY "PurchaseDate" DESC
      `, [tenantId]);

      const payments = await db.any(`
        SELECT * FROM public."Payment" WHERE "TenantID"=$1 ORDER BY "PaymentDate" DESC
      `, [tenantId]);

      const usageLogs = await db.any(`
        SELECT * FROM public."UsageLog" WHERE "TenantID"=$1 ORDER BY "UsageDateTime" DESC LIMIT 10
      `, [tenantId]);

      const combined = [
        ...utilityPurchases.map(p => ({ type: 'utilityPurchase', date: p.PurchaseDate, data: p })),
        ...payments.map(p => ({ type: 'payment', date: p.PaymentDate, data: p })),
        ...usageLogs.map(u => ({ type: 'usage', date: u.UsageDateTime, data: u })),
      ].sort((a, b) => new Date(b.date) - new Date(a.date));

      res.json(combined);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลประวัติรวม' });
    }
  });

  return router;
};
