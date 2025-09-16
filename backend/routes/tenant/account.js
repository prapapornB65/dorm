// routes/tenant/account.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  router.get('/user-role-by-uid/:uid', async (req, res) => {
    const uid = req.params.uid;
    console.log('API /user-role-by-uid uid:', uid);
    try {
      const tenant = await db.oneOrNone(
        'SELECT "TenantID" FROM "Tenant" WHERE "FirebaseUID" = $1',
        [uid]
      );
      if (tenant) return res.json({ role: 'tenant', userId: tenant.TenantID });

      const owner = await db.oneOrNone(
        'SELECT "OwnerID" FROM "Owner" WHERE "FirebaseUID" = $1',
        [uid]
      );
      if (owner) return res.json({ role: 'owner', userId: owner.OwnerID });

      const admin = await db.oneOrNone(
        'SELECT "AdminID" FROM "Admin" WHERE "FirebaseUID" = $1',
        [uid]
      );
      if (admin) return res.json({ role: 'admin', userId: admin.AdminID });

      res.status(404).json({ error: 'ไม่พบผู้ใช้ที่ตรงกับ UID นี้' });
    } catch (err) {
      console.error('Error /user-role-by-uid:', err);
      res.status(500).json({ error: err.message });
    }
  });

  // GET /tenant-info?email=xxx
  router.get('/tenant-info', async (req, res) => {
    const email = req.query.email;
    if (!email) return res.status(400).json({ error: 'Missing email parameter' });

    try {
      const tenant = await db.oneOrNone(`
        SELECT 
          t."TenantID", 
          (t."FirstName" || ' ' || t."LastName") AS "TenantName",          b."OwnerID",
          b."QrCodeUrl"
        FROM public."Tenant" t
        LEFT JOIN public."Room" r ON t."RoomNumber" = r."RoomNumber"
        LEFT JOIN public."Building" b ON r."BuildingID" = b."BuildingID"
        WHERE t."Email" = $1
      `, [email]);

      if (!tenant) return res.status(404).json({ error: 'ไม่พบ tenant ด้วย email นี้' });
      res.json(tenant);
    } catch (e) {
      console.error('Error /api/tenant-info:', e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูล tenant' });
    }
  });

  // GET /api/tenants
  router.get('/tenants', async (_req, res) => {
    try {
      const tenants = await db.any(`SELECT * FROM public."Tenant" ORDER BY "TenantID"`);
      res.json(tenants);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: e.message });
    }
  });

  // GET /api/tenant/:id
  router.get('/tenant/:id', async (req, res) => {
    const tenantId = Number(req.params.id);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const tenant = await db.oneOrNone(`
        SELECT "FirstName","LastName","Phone","BirthDate","RoomNumber","Start","End","ProfileImage"
        FROM public."Tenant" WHERE "TenantID" = $1
      `, [tenantId]);

      if (!tenant) return res.status(404).json({ error: 'ไม่พบผู้เช่านี้' });
      res.json(tenant);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: e.message });
    }
  });

  router.get('/notifications/:tenantId', async (req, res) => {
    const tenantId = parseInt(req.params.tenantId);
    try {
      const notifications = await db.any(`
        SELECT "NotificationID","Title","Message","IsRead","CreatedAt"
        FROM "Notification"
        WHERE "TenantID" = $1
        ORDER BY "CreatedAt" DESC
        LIMIT 10
      `, [tenantId]);

      res.json(notifications);
    } catch (error) {
      console.error('Error fetching notifications:', error);
      res.status(500).json({ error: 'ไม่สามารถดึงแจ้งเตือนได้' });
    }
  });

   router.get('/tenant/approval-status', async (req, res) => {
    const email = (req.query.email || '').trim();
    if (!email) return res.status(400).json({ error: 'Missing email parameter' });

    try {
      const row = await db.oneOrNone(`
        SELECT "Status","Reason","RequestDate"
        FROM public."TenantApproval"
        WHERE "Email"=$1
        ORDER BY "RequestDate" DESC
        LIMIT 1
      `, [email]);

      if (!row) {
        return res.json({ exists: false, status: 'none', approved: false });
      }
      const approved = row.Status === 'approved';
      return res.json({
        exists: true,
        status: row.Status,            // pending | approved | rejected
        approved,
        reason: row.Reason || null,
        requestDate: row.RequestDate
      });
    } catch (e) {
      console.error('approval-status error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  return router;
};
