// routes/approvals.js
const express = require('express');

module.exports = (db, admin, requireAuth, requireOwner) => {
  const router = express.Router();

  // 📄 list approvals
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

  // ✅ อนุมัติ
  router.post('/owner/approvals/:approvalId/approve', requireAuth, requireOwner, async (req, res) => {
    const { approvalId } = req.params;
    try {
      await db.tx(async t => {
        const ap = await t.oneOrNone(`
          SELECT * FROM "TenantApproval" WHERE "ApprovalID"=$1 FOR UPDATE
        `, [approvalId]);
        if (!ap) return res.status(404).json({ error: 'NOT_FOUND' });
        if (String(ap.Status).toLowerCase() !== 'pending') {
          return res.status(400).json({ error: 'NOT_PENDING' });
        }

        // ดึงข้อมูลจาก Payload
        const p = ap.Payload || {};
        const firstName = p.firstName || '';
        const lastName  = p.lastName  || '';
        const email     = ap.Email    || p.email || '';
        const phone     = p.phone     || '';
        const citizenID = p.citizenID || '';
        const roomNumber= (p.roomNumber || ap.RoomNumber || '').toString().trim().toUpperCase();

        // ถ้าจะคง FK -> ตรวจว่ามีห้องจริง
        if (roomNumber) {
          const room = await t.oneOrNone(`SELECT 1 FROM "Room" WHERE "RoomNumber"=$1`, [roomNumber]);
          if (!room) return res.status(400).json({ error: 'ROOM_NOT_FOUND' });
        }

        // สร้าง Tenant จริง
        const tenant = await t.one(`
          INSERT INTO "Tenant"
            ("FirstName","LastName","CitizenID","BirthDate","Email","Phone",
             "Username","Password","RoomNumber","Start","End","ProfileImage",
             "Role","FirebaseUID","Status")
          VALUES
            ($1,$2,$3,NULL,$4,$5,$6,'NOT_STORED_IN_DB',$7,NULL,NULL,NULL,
             'tenant',$8,'approved')
          RETURNING "TenantID","FirebaseUID"
        `, [
          firstName, lastName, citizenID, email, phone, (p.username || null),
          (roomNumber || null), p.firebaseUID
        ]);

        // claims
        if (tenant.FirebaseUID) {
          await admin.auth().setCustomUserClaims(tenant.FirebaseUID, {
            role: 'tenant',
            approved: true,
            tenantId: tenant.TenantID,
          });
        }

        // ปิดคิวอนุมัติ
        await t.none(`
          UPDATE "TenantApproval"
          SET "Status"='approved',
              "ApprovedAt"=NOW(),
              "ApprovedBy"=$1,
              "TenantID"=$2
          WHERE "ApprovalID"=$3
        `, [req.owner.id, tenant.TenantID, approvalId]);

        res.json({ ok: true, tenantId: tenant.TenantID });
      });
    } catch (e) {
      console.error('POST /owner/approvals/:id/approve error', e);
      res.status(500).json({ error: 'APPROVE_FAILED' });
    }
  });

  // ❌ ปฏิเสธ + ลบแถวจาก DB
  router.post('/owner/approvals/:approvalId/reject', requireAuth, requireOwner, async (req, res) => {
    const { approvalId } = req.params;
    const reason = (req.body?.reason || '').toString().trim().slice(0, 500);
    try {
      await db.tx(async t => {
        const ap = await t.oneOrNone(`
          SELECT "ApprovalID","TenantID","Payload" FROM "TenantApproval" WHERE "ApprovalID"=$1
        `, [approvalId]);
        if (!ap) return res.status(404).json({ error: 'NOT_FOUND' });

        // ถ้าเผลอสร้าง Tenant ไปแล้ว (ไม่น่ามีในสถานะ pending) → ลบทิ้งด้วย
        if (ap.TenantID) {
          await t.none(`DELETE FROM "Tenant" WHERE "TenantID"=$1`, [ap.TenantID]);
        }

        // เก็บ log เหตุผลก่อนลบ (ถ้าต้องการเก็บประวัติ ให้ย้ายไปตาราง History)
        await t.none(`
          INSERT INTO "TenantApprovalHistory"
            ("ApprovalID","Action","Reason","LogAt","Payload")
          VALUES ($1,'reject',$2,NOW(),$3::jsonb)
        `, [approvalId, reason || null, ap.Payload || {}]);

        // ลบคำขอออกจากคิว
        await t.none(`DELETE FROM "TenantApproval" WHERE "ApprovalID"=$1`, [approvalId]);
      });

      res.json({ ok: true });
    } catch (e) {
      console.error('POST /owner/approvals/:id/reject error', e);
      res.status(500).json({ error: 'REJECT_FAILED' });
    }
  });

  return router;
};
