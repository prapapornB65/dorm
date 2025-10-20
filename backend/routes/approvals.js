// routes/approvals.js
const express = require('express');

module.exports = (db, admin, requireAuth, requireOwner) => {
  const router = express.Router();

  // helper: gen temp password
  function genTempPassword(len = 12) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%';
    let out = '';
    for (let i = 0; i < len; i++) out += chars[Math.floor(Math.random() * chars.length)];
    return out;
  }

  // 📄 list approvals by status (pending|approved|rejected)
  router.get('/owner/approvals', requireAuth, requireOwner, async (req, res) => {
    const { status = 'pending', limit = 50 } = req.query;
    try {
      const rows = await db.any(`
        SELECT "ApprovalID","TenantID","FullName","Email","Status","Reason",
               "RequestDate","ApprovedAt","ApprovedBy","RoomNumber","Payload"
        FROM "TenantApproval"
        WHERE LOWER("Status") = $1
        ORDER BY "ApprovalID" DESC
        LIMIT $2
      `, [String(status).toLowerCase(), Number(limit)]);
      res.json({ ok: true, items: rows });
    } catch (e) {
      console.error('GET /owner/approvals error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ✅ approve: create Firebase user if needed, insert Tenant, set claims, update Approval
  router.post('/owner/approvals/:approvalId/approve', requireAuth, requireOwner, async (req, res) => {
    const { approvalId } = req.params;
    try {
      const out = await db.tx(async t => {
        const ap = await t.oneOrNone(`
          SELECT * FROM "TenantApproval" WHERE "ApprovalID"=$1 FOR UPDATE
        `, [approvalId]);
        if (!ap) return { status: 404, body: { error: 'NOT_FOUND' } };

        if (String(ap.Status || '').toLowerCase() !== 'pending') {
          return { status: 400, body: { error: 'NOT_PENDING' } };
        }

        const p = ap.Payload || {};
        const firstName = (p.firstName || '').trim();
        const lastName  = (p.lastName  || '').trim();
        const email     = (ap.Email || p.email || '').toLowerCase().trim();
        const phone     = (p.phone || '').trim() || null;
        const citizenID = (p.citizenID || '').trim() || null;
        const username  = p.username || null;
        const roomNumber= (p.roomNumber || ap.RoomNumber || '').toString().trim().toUpperCase();

        if (!firstName || !lastName || !email || !roomNumber) {
          return { status: 400, body: { error: 'MISSING_FIELDS' } };
        }

        // (ออปชัน) ตรวจว่าห้องมีอยู่จริง
        // const room = await t.oneOrNone(`SELECT 1 FROM "Room" WHERE "RoomNumber"=$1`, [roomNumber]);
        // if (!room) return { status: 400, body: { error: 'ROOM_NOT_FOUND' } };

        // create Firebase user if not exists in payload
        let firebaseUID = p.firebaseUID || null;
        let tempPassword = null;
        if (!firebaseUID) {
          const pwd = genTempPassword();
          const fb = await admin.auth().createUser({
            email,
            password: pwd,
            displayName: `${firstName} ${lastName}`.trim()
          });
          firebaseUID = fb.uid;
          tempPassword = pwd;
        }

        // insert Tenant
        const tenant = await t.one(`
          INSERT INTO "Tenant"
            ("FirstName","LastName","CitizenID","BirthDate","Email","Phone",
             "Username","Password","RoomNumber","Start","End","ProfileImage",
             "Role","FirebaseUID","Status","ApprovedAt","ApprovedByOwnerID")
          VALUES
            ($1,$2,$3,NULL,$4,$5,$6,'NOT_STORED_IN_DB',$7,NULL,NULL,NULL,
             'tenant',$8,'approved',NOW(),$9)
          RETURNING "TenantID","FirebaseUID"
        `, [firstName, lastName, citizenID, email, phone, username, roomNumber, firebaseUID, req.owner.id]);

        // set custom claims
        if (tenant.FirebaseUID) {
          await admin.auth().setCustomUserClaims(tenant.FirebaseUID, {
            role: 'tenant',
            approved: true,
            tenantId: Number(tenant.TenantID),
          });
        }

        // update approval -> approved
        await t.none(`
          UPDATE "TenantApproval"
          SET "Status"='approved',
              "ApprovedAt"=NOW(),
              "ApprovedBy"=$1,
              "TenantID"=$2
          WHERE "ApprovalID"=$3
        `, [req.owner.id, tenant.TenantID, approvalId]);

        return { status: 200, body: { ok: true, tenantId: tenant.TenantID, tempPassword } };
      });

      return res.status(out.status).json(out.body);
    } catch (e) {
      console.error('POST /owner/approvals/:id/approve error', e);
      res.status(500).json({ error: 'APPROVE_FAILED' });
    }
  });

  // ❌ reject: only pending -> mark as rejected (keep row), save reason
  router.post('/owner/approvals/:approvalId/reject', requireAuth, requireOwner, async (req, res) => {
    const { approvalId } = req.params;
    const reason = (req.body?.reason || '').toString().trim().slice(0, 500) || null;

    try {
      const out = await db.tx(async t => {
        const ap = await t.oneOrNone(`
          SELECT * FROM "TenantApproval" WHERE "ApprovalID"=$1 FOR UPDATE
        `, [approvalId]);
        if (!ap) return { status: 404, body: { error: 'NOT_FOUND' } };

        if (String(ap.Status || '').toLowerCase() !== 'pending') {
          return { status: 400, body: { error: 'NOT_PENDING' } };
        }

        // write history (ออปชัน ถ้ามีตาราง)
        try {
          await t.none(`
            INSERT INTO "TenantApprovalHistory"
              ("ApprovalID","Action","Reason","LogAt","Payload")
            VALUES ($1,'reject',$2,NOW(),$3::jsonb)
          `, [approvalId, reason, ap.Payload || {}]);
        } catch (_) { /* ถ้าไม่มีตาราง history ก็ข้ามได้ */ }

        // mark as rejected (ไม่ลบแถว)
        await t.none(`
          UPDATE "TenantApproval"
          SET "Status"='rejected',
              "ApprovedAt"=NOW(),
              "ApprovedBy"=$1,
              "Reason"=$2
          WHERE "ApprovalID"=$3
        `, [req.owner.id, reason, approvalId]);

        // ถ้า payload เคยมี firebaseUID (กรณีพิเศษ) -> ปิดสิทธิ์ไว้
        const uid = ap.Payload?.firebaseUID;
        if (uid) {
          await admin.auth().setCustomUserClaims(uid, { role: 'tenant', approved: false });
        }

        return { status: 200, body: { ok: true } };
      });

      return res.status(out.status).json(out.body);
    } catch (e) {
      console.error('POST /owner/approvals/:id/reject error', e);
      res.status(500).json({ error: 'REJECT_FAILED' });
    }
  });

  // 🔎 status by approvalId (หน้า Waiting)
  router.get('/tenant-approval/:approvalId/status', async (req, res) => {
    const { approvalId } = req.params;
    try {
      const row = await db.oneOrNone(`
        SELECT "Status","TenantID" FROM "TenantApproval" WHERE "ApprovalID"=$1
      `, [approvalId]);
      if (!row) return res.status(404).json({ error: 'NOT_FOUND' });
      res.json({
        status: String(row.Status || 'pending').toLowerCase(),
        tenantId: row.TenantID
      });
    } catch (e) {
      console.error('GET /tenant-approval/:approvalId/status error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // 🔎 (ใหม่) status by email — สำหรับหน้า Login ตรวจสอบสถานะ (ไม่ต้อง auth)
  router.get('/tenant-approval/status-by-email', async (req, res) => {
    const email = (req.query.email || '').toString().trim().toLowerCase();
    if (!email) return res.status(400).json({ error: 'EMAIL_REQUIRED' });
    try {
      const row = await db.oneOrNone(`
        SELECT "ApprovalID","Status","Reason"
        FROM "TenantApproval"
        WHERE LOWER("Email")=$1
        ORDER BY "ApprovalID" DESC
        LIMIT 1
      `, [email]);
      if (!row) return res.status(404).json({ error: 'NOT_FOUND' });
      res.json({
        approvalId: row.ApprovalID,
        status: String(row.Status || 'pending').toLowerCase(),
        reason: row.Reason || null
      });
    } catch (e) {
      console.error('GET /tenant-approval/status-by-email error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  return router;
};
