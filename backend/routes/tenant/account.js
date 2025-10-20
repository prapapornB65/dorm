// routes/tenant/account.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // ---------------- helpers ----------------
  async function ensureProvisioned(tenantId) {
    // Wallet
    await db.none(`
      INSERT INTO public."Wallet"("TenantID","Balance","created_at","updated_at")
      SELECT $1, 0, NOW(), NOW()
      WHERE NOT EXISTS (
        SELECT 1 FROM public."Wallet" WHERE "TenantID" = $1
      )
    `, [tenantId]);

    // UnitBalance
    await db.none(`
      INSERT INTO public."UnitBalance"("TenantID","ElectricUnit","WaterUnit","LastUpdated")
      SELECT $1, 0, 0, NOW()
      WHERE NOT EXISTS (
        SELECT 1 FROM public."UnitBalance" WHERE "TenantID" = $1
      )
    `, [tenantId]);

    return true;
  }

  // คืนสถานะจาก TenantApproval เป็นหลัก
  async function getStatusFromApproval({ tenantId, email }) {
    if (!tenantId && !email) return { status: 'not_found' };

    const ap = await db.oneOrNone(`
  SELECT "Status","TenantID","ApprovalID","ApprovedAt","RequestDate","Email"
  FROM public."TenantApproval"
  WHERE ($1::int  IS NOT NULL AND "TenantID" = $1)
     OR ($2::text IS NOT NULL AND lower("Email") = lower($2))
  ORDER BY
    (LOWER("Status") = 'approved') DESC,                  -- ✅ ให้ approved มาก่อน
    COALESCE("ApprovedAt","RequestDate") DESC
  LIMIT 1
`, [tenantId || null, email || null]);


    if (!ap) return { status: 'not_found', tenantId };

    const s = String(ap.Status || '').trim().toLowerCase();
    if (s === 'approved') return { status: 'approved', tenantId: ap.TenantID || tenantId, approvalId: ap.ApprovalID || null };
    if (s === 'rejected') return { status: 'rejected', tenantId: ap.TenantID || tenantId, approvalId: ap.ApprovalID || null };
    return { status: 'pending', tenantId: ap.TenantID || tenantId, approvalId: ap.ApprovalID || null };
  }

  // ---------- Provision on-demand ----------
  router.post('/tenant/:id/provision', async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) {
      return res.status(400).json({ error: 'invalid tenant id' });
    }
    try {
      const exists = await db.oneOrNone(`SELECT 1 FROM public."Tenant" WHERE "TenantID"=$1`, [id]);
      if (!exists) return res.status(404).json({ error: 'TENANT_NOT_FOUND' });

      await ensureProvisioned(id);
      return res.json({ ok: true });
    } catch (e) {
      console.error('POST /tenant/:id/provision error', e);
      return res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ---------- Role lookup by Firebase UID ----------
  router.get('/user-role-by-uid/:uid', async (req, res) => {
    const uid = req.params.uid;
    console.log('API /user-role-by-uid uid:', uid);
    try {
      const tenant = await db.oneOrNone(
        'SELECT "TenantID" FROM "Tenant" WHERE "FirebaseUID" = $1',
        [uid]
      );
      if (tenant) {
        const id = Number(tenant.TenantID);
        return res.json({ role: 'tenant', userId: id, id });
      }

      const owner = await db.oneOrNone(
        'SELECT "OwnerID" FROM "Owner" WHERE "FirebaseUID" = $1',
        [uid]
      );
      if (owner) {
        const id = Number(owner.OwnerID);
        return res.json({ role: 'owner', userId: id, id });
      }

      const admin = await db.oneOrNone(
        'SELECT "AdminID" FROM "Admin" WHERE "FirebaseUID" = $1',
        [uid]
      );
      if (admin) {
        const id = Number(admin.AdminID);
        return res.json({ role: 'admin', userId: id, id });
      }

      res.status(404).json({ error: 'ไม่พบผู้ใช้ที่ตรงกับ UID นี้' });
    } catch (err) {
      console.error('Error /user-role-by-uid:', err);
      res.status(500).json({ error: err.message });
    }
  });

  // ---------- Tenant info by email ----------
  router.get('/tenant-info', async (req, res) => {
    const email = (req.query.email || '').toString().trim();
    if (!email) {
      return res.status(400).json({ error: 'Missing email parameter' });
    }

    try {
      const tenant = await db.oneOrNone(`
        SELECT 
          t."TenantID",
          (COALESCE(t."FirstName",'') || ' ' || COALESCE(t."LastName",'')) AS "TenantName",
          b."OwnerID",
          b."QrCodeUrl"
        FROM public."Tenant"   t
        LEFT JOIN public."Room"     r ON r."RoomNumber"  = t."RoomNumber"
        LEFT JOIN public."Building" b ON b."BuildingID"  = r."BuildingID"
        WHERE LOWER(t."Email") = LOWER($1)
        LIMIT 1
      `, [email]);

      if (!tenant) {
        return res.status(404).json({ error: 'ไม่พบ tenant ด้วย email นี้' });
      }
      res.json(tenant);
    } catch (e) {
      console.error('Error /api/tenant-info:', e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูล tenant' });
    }
  });

  // ---------- List tenants ----------
  router.get('/tenants', async (_req, res) => {
    try {
      const tenants = await db.any(`SELECT * FROM public."Tenant" ORDER BY "TenantID"`);
      res.json(tenants);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: e.message });
    }
  });

  // ---------- Get tenant snapshot ----------
  router.get('/tenant/:id', async (req, res) => {
    const tenantId = Number(req.params.id);
    if (!Number.isInteger(tenantId)) {
      return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });
    }

    try {
      const tenant = await db.oneOrNone(`
        SELECT "FirstName","LastName","Phone","BirthDate","RoomNumber","Start","End","ProfileImage"
        FROM public."Tenant"
        WHERE "TenantID" = $1
      `, [tenantId]);

      if (!tenant) return res.status(404).json({ error: 'ไม่พบผู้เช่านี้' });
      res.json(tenant);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: e.message });
    }
  });

  // ---------- Notifications ----------
  router.get('/notifications/:tenantId', async (req, res) => {
    const tenantId = parseInt(req.params.tenantId, 10);
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

  // ---------- Approval status (by email, simple) ----------
  router.get('/tenant/approval-status', async (req, res) => {
    const email = (req.query.email || '').toString().trim();
    if (!email) return res.status(400).json({ error: 'Missing email parameter' });

    try {
      const row = await db.oneOrNone(`
        SELECT "Status","Reason","RequestDate"
        FROM public."TenantApproval"
        WHERE LOWER("Email") = LOWER($1)
        ORDER BY "RequestDate" DESC
        LIMIT 1
      `, [email]);

      if (!row) {
        return res.json({ exists: false, status: 'none', approved: false });
      }
      const approved = String(row.Status).toLowerCase() === 'approved';
      return res.json({
        exists: true,
        status: String(row.Status || '').toLowerCase(), // pending | approved | rejected
        approved,
        reason: row.Reason || null,
        requestDate: row.RequestDate
      });
    } catch (e) {
      console.error('approval-status error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ---------- Lookup approval (by email) ----------
  router.get('/tenant-approval/lookup', async (req, res) => {
    const email = (req.query.email || '').toString().trim();
    if (!email) return res.status(400).json({ error: 'Missing email parameter' });

    try {
      const row = await db.oneOrNone(`
        SELECT "Status","Reason","RequestDate","TenantID","ApprovalID"
        FROM public."TenantApproval"
        WHERE LOWER("Email") = LOWER($1)
        ORDER BY "RequestDate" DESC
        LIMIT 1
      `, [email]);

      if (!row) return res.status(404).json({ error: 'NOT_FOUND' });

      res.json({
        approvalId: row.ApprovalID ?? null,
        tenantId: row.TenantID ?? null,
        status: String(row.Status || 'pending').toLowerCase(),
        reason: row.Reason || null,
        requestDate: row.RequestDate
      });
    } catch (e) {
      console.error('lookup alias error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ---------- NEW: tenant status (by tenantId) → ใช้ TenantApproval เป็นหลัก ----------
  router.get('/tenant/:id/status', async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) {
      return res.status(400).json({ error: 'invalid tenant id' });
    }
    try {
      console.log('[STATUS] id =', id);

      const fromAp = await getStatusFromApproval({ tenantId: id });

      if (fromAp.status === 'approved' || fromAp.status === 'rejected') {
        // กรณีชัดเจน รีเทิร์นได้เลย
        return res.json({
          status: fromAp.status,
          tenantId: fromAp.tenantId || id,
          approvalId: fromAp.approvalId || null
        });
      }

      if (fromAp.status === 'pending') {
        // กันเคส pending แต่จริง ๆ ระบบหลักอนุมัติแล้ว
        const trow = await db.oneOrNone(`
    SELECT TRIM(COALESCE("Status",'approved')) AS "Status"
    FROM public."Tenant"
    WHERE "TenantID" = $1
    LIMIT 1
  `, [id]);

        if (trow) {
          const ts = String(trow.Status || 'approved').trim().toLowerCase();
          if (ts === 'approved') {
            return res.json({
              status: 'approved',
              tenantId: fromAp.tenantId || id,
              approvalId: fromAp.approvalId || null
            });
          }
          if (ts === 'rejected') {
            return res.json({
              status: 'rejected',
              tenantId: fromAp.tenantId || id,
              approvalId: fromAp.approvalId || null
            });
          }
        }

        // ถ้า tenant ยังไม่ approved จริง ก็คง pending ตาม approval
        return res.json({
          status: 'pending',
          tenantId: fromAp.tenantId || id,
          approvalId: fromAp.approvalId || null
        });
      }

      // ไม่พบใน approval → ใช้ fallback เดิม



      // 2) fallback จากตาราง Tenant (เดิม)
      const row = await db.oneOrNone(`
      SELECT TRIM(COALESCE("Status", 'approved')) AS "Status"
      FROM public."Tenant"
      WHERE "TenantID" = $1
      LIMIT 1
    `, [id]);

      console.log('[STATUS] from tenant =', row);
      if (!row) return res.status(404).json({ error: 'TENANT_NOT_FOUND' });

      const s = String(row.Status || 'approved').trim().toLowerCase();
      return res.json({ status: s });
    } catch (e) {
      console.error('GET /tenant/:id/status error', e);
      return res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ---------- NEW: tenant status (by email) ----------
  router.get('/tenant-status-by-email', async (req, res) => {
    const email = (req.query.email || '').toString().trim();
    if (!email) return res.status(400).json({ error: 'email required' });
    try {
      const out = await getStatusFromApproval({ email });
      return res.json(out);
    } catch (e) {
      console.error('GET /tenant-status-by-email error', e);
      return res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ---------- fixUrlHost helper ----------
  function fixUrlHost(raw, req) {
    if (!raw) return raw;
    try {
      const u = new URL(raw);
      if (u.hostname === 'localhost' || u.hostname === '127.0.0.1') {
        const base = process.env.PUBLIC_BASE_URL
          ? new URL(process.env.PUBLIC_BASE_URL)
          : new URL(`${req.protocol}://${req.get('host')}`);
        u.protocol = base.protocol;
        u.hostname = base.hostname;
        u.port = base.port || u.port;
        return u.toString();
      }
      return raw;
    } catch {
      return raw;
    }
  }

  // ---------- Contact owner ----------
  router.get('/contact-owner/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId) || tenantId <= 0) {
      return res.status(400).json({ error: 'INVALID_TENANT_ID' });
    }

    try {
      await ensureProvisioned(tenantId, db);

      const row = await db.oneOrNone(`
        SELECT 
          o."OwnerID",
          o."FirstName", o."LastName",
          o."Email", o."Phone", o."CitizenID",
          b."QrCodeUrl" AS "QrCodeUrl",
          o."ApiKey"    AS "ApiKey",
          o."ProjectID" AS "ProjectID",
          (COALESCE(o."FirstName",'') || ' ' || COALESCE(o."LastName",'')) AS "OwnerName"
        FROM public."Tenant"   t
        LEFT JOIN public."Room"     r ON r."RoomNumber" = t."RoomNumber"
        LEFT JOIN public."Building" b ON b."BuildingID" = r."BuildingID"
        LEFT JOIN public."Owner"    o ON o."OwnerID"    = b."OwnerID"
        WHERE t."TenantID" = $1
        LIMIT 1
      `, [tenantId]);

      if (!row || !row.OwnerID) {
        return res.status(404).json({ error: 'OWNER_NOT_FOUND' });
      }

      return res.json({
        OwnerID: row.OwnerID,
        FirstName: row.FirstName,
        LastName: row.LastName,
        Email: row.Email,
        Phone: row.Phone,
        CitizenID: row.CitizenID,
        QrCodeUrl: fixUrlHost(row.QrCodeUrl, req),
        OwnerName: row.OwnerName,
        ApiKey: row.ApiKey || null,
        ProjectID: row.ProjectID || null
      });
    } catch (e) {
      console.error('GET /contact-owner/:tenantId error:', e);
      return res.status(500).json({ error: 'DB_ERROR', message: e.message });
    }
  });

  // ---------- Owner snapshot (with last building QR) ----------
  router.get('/owner/:ownerId', async (req, res) => {
    const ownerId = Number(req.params.ownerId);
    if (!Number.isInteger(ownerId) || ownerId <= 0) {
      return res.status(400).json({ error: true, message: 'INVALID_OWNER_ID' });
    }

    const fixUrl = (raw) => {
      if (!raw) return raw;
      try {
        const u = new URL(raw);
        if (u.hostname === 'localhost' || u.hostname === '127.0.0.1') {
          const base = process.env.PUBLIC_BASE_URL
            ? new URL(process.env.PUBLIC_BASE_URL)
            : new URL(`${req.protocol}://${req.get('host')}`);
          u.protocol = base.protocol;
          u.hostname = base.hostname;
          u.port = base.port || u.port;
          return u.toString();
        }
        return raw;
      } catch { return raw; }
    };

    try {
      const row = await db.oneOrNone(`
        SELECT 
          o."OwnerID",
          o."FirstName", o."LastName",
          o."ApiKey"    AS "ApiKey",
          o."ProjectID" AS "ProjectID",
          (COALESCE(o."FirstName",'') || ' ' || COALESCE(o."LastName",'')) AS "OwnerName",
          b."QrCodeUrl" AS "QrCodeUrl"
        FROM public."Owner" o
        LEFT JOIN LATERAL (
          SELECT "QrCodeUrl"
          FROM public."Building"
          WHERE "OwnerID" = o."OwnerID"
          ORDER BY "BuildingID" DESC
          LIMIT 1
        ) b ON TRUE
        WHERE o."OwnerID" = $1
        LIMIT 1
      `, [ownerId]);

      if (!row) {
        return res.status(404).json({ error: true, message: 'OWNER_NOT_FOUND' });
      }

      return res.json({
        error: false,
        ownerName: row.OwnerName,
        apiKey: row.ApiKey || null,
        projectId: row.ProjectID || null,
        qrCodeUrl: fixUrl(row.QrCodeUrl) || null
      });
    } catch (e) {
      console.error('GET /owner/:ownerId error:', e);
      return res.status(500).json({ error: true, message: e.message });
    }
  });

  return router;
};
