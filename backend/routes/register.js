// routes/register.js
const express = require('express');

module.exports = (db, admin) => {
  const router = express.Router();

  // ---------- helpers ----------
  const required = (src, keys) =>
    keys.every(k => (src?.[k] ?? '').toString().trim().length > 0);

  async function createOrGetFirebaseUser({ email, password, displayName }) {
    try {
      return await admin.auth().createUser({
        email,
        password,
        displayName,
        // phoneNumber ต้องเป็น E.164 (+66...) ถ้าไม่ชัวร์อย่าใส่
      });
    } catch (e) {
      if (e.code === 'auth/email-already-exists') {
        return await admin.auth().getUserByEmail(email);
      }
      throw e;
    }
  }

  // ---------- middlewares: auth / owner ----------
  async function requireAuth(req, res, next) {
    try {
      const authHeader = req.headers.authorization || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
      if (!token) return res.status(401).json({ error: 'MISSING_BEARER' });
      req.decoded = await admin.auth().verifyIdToken(token);
      next();
    } catch (e) {
      return res.status(401).json({ error: 'INVALID_TOKEN' });
    }
  }

  async function requireOwner(req, res, next) {
    try {
      const uid = req.decoded.uid || req.decoded.user_id || req.decoded.sub;
      const owner = await db.oneOrNone(
        `SELECT "OwnerID" AS id FROM "Owner" WHERE "FirebaseUID"=$1`, [uid]
      );
      if (!owner) return res.status(403).json({ error: 'NOT_OWNER' });
      req.owner = owner;
      next();
    } catch (e) {
      console.error('requireOwner error:', e);
      return res.status(500).json({ error: 'OWNER_LOOKUP_FAILED' });
    }
  }

  // ---------- สมัคร "ผู้เช่า" ----------
  router.post('/tenant/register', async (req, res) => {
  const b = req.body || {};
  if (!required(b, ['firstName','lastName','email','phone','citizenID','password','roomNumber'])) {
    return res.status(400).json({ error: 'MISSING_FIELDS' });
  }

  try {
    const displayName = `${b.firstName} ${b.lastName}`.trim();
    const fbUser = await createOrGetFirebaseUser({
      email: b.email, password: b.password, displayName
    });

    // เก็บข้อมูลสำคัญไว้ใน Payload (รวม FirebaseUID)
    const payload = {
      firstName: b.firstName,
      lastName: b.lastName,
      citizenID: b.citizenID,
      phone: b.phone,
      username: b.username || null,
      roomNumber: b.roomNumber,
      firebaseUID: fbUser.uid,
    };

    const ap = await db.one(`
      INSERT INTO "TenantApproval"
        ("TenantID","RoomNumber","FullName","Email","Status","Reason","RequestDate","ApprovedAt","ApprovedBy","Payload")
      VALUES
        (NULL,$1,$2,$3,'pending',NULL,NOW(),NULL,NULL,$4::jsonb)
      RETURNING "ApprovalID"
    `, [b.roomNumber, displayName, b.email, JSON.stringify(payload)]);

    // ตั้ง custom claims ไว้ก่อน (ยังไม่อนุมัติ)
    await admin.auth().setCustomUserClaims(fbUser.uid, {
      role: 'tenant',
      approved: false
    });

    // ตอบกลับด้วย approvalId เพื่อใช้ติดตามสถานะ
    return res.status(201).json({
      ok: true,
      status: 'pending',
      approvalId: ap.ApprovalID,
      uid: fbUser.uid,
    });
  } catch (e) {
    console.error('POST /tenant/register error', e);
    return res.status(500).json({ error: 'REGISTER_FAILED', detail: String(e.message || e) });
  }
});


  // ---------- สมัคร "เจ้าของหอพัก" ----------
  router.post('/owner/register', async (req, res) => {
    const b = req.body || {};
    if (!required(b, ['firstName','lastName','email','phone','citizenId','password'])) {
      return res.status(400).json({ error: 'MISSING_FIELDS' });
    }

    try {
      const displayName = `${b.firstName} ${b.lastName}`.trim();
      const fbUser = await createOrGetFirebaseUser({
        email: b.email, password: b.password, displayName
      });

      const row = await db.one(`
        INSERT INTO "Owner"
          ("FirstName","LastName","Email","Phone","CitizenID","UserName",
           "Password","ApiKey","ProjectID","StartDate","EndDate","FirebaseUID")
        VALUES
          ($1,$2,$3,$4,$5,$6,'NOT_STORED_IN_DB',$7,$8,NOW(),NULL,$9)
        RETURNING "OwnerID"
      `, [
        b.firstName, b.lastName, b.email, b.phone, b.citizenId,
        (b.username || null),
        (b.apiKey || null),
        (b.projectId || null),
        fbUser.uid,
      ]);

      return res.status(201).json({
        ok: true,
        role: 'owner',
        userId: row.OwnerID,
        uid: fbUser.uid,
      });
    } catch (e) {
      console.error('POST /owner/register error', e);
      return res.status(500).json({ error: 'REGISTER_FAILED', detail: String(e.message || e) });
    }
  });

  // ---------- map uid -> role/id ----------
  router.get('/user-role-by-uid/:uid', async (req, res) => {
    const { uid } = req.params;
    try {
      const t = await db.oneOrNone(
        `SELECT "TenantID" AS id FROM "Tenant" WHERE "FirebaseUID"=$1`, [uid]
      );
      if (t) return res.json({ role: 'tenant', userId: t.id });

      const o = await db.oneOrNone(
        `SELECT "OwnerID" AS id FROM "Owner" WHERE "FirebaseUID"=$1`, [uid]
      );
      if (o) return res.json({ role: 'owner', userId: o.id });

      const a = await db.oneOrNone(
        `SELECT "AdminID" AS id FROM "Admin" WHERE "FirebaseUID"=$1`, [uid]
      );
      if (a) return res.json({ role: 'admin', userId: a.id });

      return res.status(404).json({ error: 'NOT_FOUND' });
    } catch (e) {
      console.error('GET /user-role-by-uid error', e);
      return res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ---------- tenant status (สำหรับหน้า Waiting) ----------
  router.get('/tenant/:tenantId/status', requireAuth, async (req, res) => {
    const { tenantId } = req.params;
    try {
      const row = await db.oneOrNone(
        `SELECT COALESCE("Status",'pending') AS status FROM "Tenant" WHERE "TenantID"=$1`,
        [tenantId]
      );
      if (!row) return res.status(404).json({ error: 'NOT_FOUND' });
      res.json({ status: String(row.status).toLowerCase() });
    } catch (e) {
      console.error('GET /tenant/:id/status error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ---------- Owner approvals ----------
  // คิวรออนุมัติ 

// อนุมัติ -> ย้ายเข้า Tenant + อัปเดต TenantApproval
router.post('/owner/approvals/:approvalId/approve', requireAuth, requireOwner, async (req, res) => {
  const { approvalId } = req.params;
  try {
    const ap = await db.oneOrNone(`
      SELECT * FROM "TenantApproval" WHERE "ApprovalID"=$1
    `, [approvalId]);
    if (!ap) return res.status(404).json({ error: 'NOT_FOUND' });
    if ((ap.Status || '').toLowerCase() === 'approved') {
      return res.json({ ok: true, tenantId: ap.TenantID });
    }

    const p = ap.Payload || {};
    const firstName  = p.firstName || (ap.FullName || '').split(' ')[0] || '';
    const lastName   = p.lastName  || (ap.FullName || '').split(' ').slice(1).join(' ') || '';
    const citizenID  = p.citizenID || null;
    const phone      = p.phone     || null;
    const username   = p.username  || null;
    const roomNumber = p.roomNumber || ap.RoomNumber || null;
    const firebaseUID= p.firebaseUID;

    // สร้าง Tenant ตัวจริง
    const ten = await db.one(`
      INSERT INTO "Tenant"
        ("FirstName","LastName","CitizenID","BirthDate","Email","Phone",
         "Username","Password","RoomNumber","Start","End","ProfileImage",
         "Role","FirebaseUID","Status","ApprovedAt","ApprovedByOwnerID")
      VALUES
        ($1,$2,$3,NULL,$4,$5,$6,'NOT_STORED_IN_DB',$7,NULL,NULL,NULL,'tenant',$8,'approved',NOW(),$9)
      RETURNING "TenantID"
    `, [firstName, lastName, citizenID, ap.Email, phone, username, roomNumber, firebaseUID, req.owner.id]);

    // ผูกกลับเข้า TenantApproval
    await db.none(`
      UPDATE "TenantApproval"
      SET "Status"='approved', "ApprovedAt"=NOW(), "ApprovedBy"=$1, "TenantID"=$2
      WHERE "ApprovalID"=$3
    `, [req.owner.id, ten.TenantID, approvalId]);

    // ปลดล็อก claims
    if (firebaseUID) {
      await admin.auth().setCustomUserClaims(firebaseUID, {
        role: 'tenant',
        approved: true,
        tenantId: Number(ten.TenantID),
      });
    }

    res.json({ ok: true, tenantId: ten.TenantID });
  } catch (e) {
    console.error('POST /owner/approvals/:approvalId/approve error', e);
    res.status(500).json({ error: 'APPROVE_FAILED' });
  }
});

// ปฏิเสธ
router.post('/owner/approvals/:approvalId/reject', requireAuth, requireOwner, async (req, res) => {
  const { approvalId } = req.params;
  const { reason = null } = req.body || {};
  try {
    const ap = await db.oneOrNone(`SELECT * FROM "TenantApproval" WHERE "ApprovalID"=$1`, [approvalId]);
    if (!ap) return res.status(404).json({ error: 'NOT_FOUND' });

    await db.none(`
      UPDATE "TenantApproval"
      SET "Status"='rejected', "ApprovedAt"=NOW(), "ApprovedBy"=$1, "Reason"=$2
      WHERE "ApprovalID"=$3
    `, [req.owner.id, reason, approvalId]);

    // (ออปชัน) กันการใช้งานฝั่ง claims
    const uid = ap.Payload?.firebaseUID;
    if (uid) {
      await admin.auth().setCustomUserClaims(uid, { role: 'tenant', approved: false });
    }

    res.json({ ok: true });
  } catch (e) {
    console.error('POST /owner/approvals/:approvalId/reject error', e);
    res.status(500).json({ error: 'REJECT_FAILED' });
  }
});

// เช็กสถานะตาม approvalId  (ใช้ตอนแอปแสดง "รออนุมัติ")
router.get('/tenant-approval/:approvalId/status', requireAuth, async (req, res) => {
  const { approvalId } = req.params;
  try {
    const row = await db.oneOrNone(`
      SELECT "Status","TenantID" FROM "TenantApproval" WHERE "ApprovalID"=$1
    `, [approvalId]);
    if (!row) return res.status(404).json({ error: 'NOT_FOUND' });
    res.json({ status: String(row.Status || 'pending').toLowerCase(), tenantId: row.TenantID });
  } catch (e) {
    console.error('GET /tenant-approval/:approvalId/status error', e);
    res.status(500).json({ error: 'DB_ERROR' });
  }
});



  router.post('/owner/approvals/:tenantId/approve', requireAuth, requireOwner, async (req, res) => {
    const { tenantId } = req.params;
    try {
      const row = await db.oneOrNone(
        `UPDATE "Tenant"
         SET "Status"='approved', "ApprovedAt"=NOW(), "ApprovedByOwnerID"=$1
         WHERE "TenantID"=$2
         RETURNING "FirebaseUID","TenantID"`,
        [req.owner.id, tenantId]
      );
      if (!row) return res.status(404).json({ error: 'NOT_FOUND' });

      await admin.auth().setCustomUserClaims(row.FirebaseUID, {
        role: 'tenant',
        approved: true,
        tenantId: Number(row.TenantID),
      });

      res.json({ ok: true });
    } catch (e) {
      console.error('POST /owner/approvals/:tenantId/approve error', e);
      res.status(500).json({ error: 'APPROVE_FAILED' });
    }
  });

  router.post('/owner/approvals/:tenantId/reject', requireAuth, requireOwner, async (req, res) => {
    const { tenantId } = req.params;
    try {
      const row = await db.oneOrNone(
        `UPDATE "Tenant"
         SET "Status"='rejected', "ApprovedAt"=NULL, "ApprovedByOwnerID"=NULL
         WHERE "TenantID"=$1
         RETURNING "FirebaseUID"`,
        [tenantId]
      );
      if (!row) return res.status(404).json({ error: 'NOT_FOUND' });

      await admin.auth().setCustomUserClaims(row.FirebaseUID, {
        role: 'tenant',
        approved: false,
        tenantId: Number(tenantId),
      });

      res.json({ ok: true });
    } catch (e) {
      console.error('POST /owner/approvals/:tenantId/reject error', e);
      res.status(500).json({ error: 'REJECT_FAILED' });
    }
  });

  return router;
};
