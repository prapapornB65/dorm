// routes/register.js
const express = require('express');
const bcrypt = require('bcryptjs');

module.exports = (db, admin) => {
  const router = express.Router();

  // ---------- config: เก็บรหัสแบบ plain หรือ hash ----------
  // default = true เพื่อให้เห็นเหมือนสกรีนช็อต (คำเตือน: ไม่ปลอดภัย!)
  const STORE_PLAINTEXT_PASSWORDS = (process.env.STORE_PLAINTEXT_PASSWORDS ?? 'true') !== 'false';

  // ---------- helpers ----------
  const required = (src, keys) =>
    keys.every(k => (src?.[k] ?? '').toString().trim().length > 0);

  function genTempPassword(len = 12) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%';
    let out = '';
    for (let i = 0; i < len; i++) out += chars[Math.floor(Math.random() * chars.length)];
    return out;
  }

  const normalizeNotNull = (v, fallback = '-') => {
    const s = (v ?? '').toString().trim();
    return s.length > 0 ? s : fallback;
  };

  const makeUsernameBase = (email, roomNumber, firstName) => {
    const local = (email || '').split('@')[0].replace(/[^a-zA-Z0-9_.-]/g, '');
    const room = (roomNumber || '').toString().replace(/\s+/g, '');
    const base1 = local || (firstName || '').toLowerCase() || 'user';
    return room ? `${base1}_${room}` : base1;
  };

  async function ensureUniqueUsername(t, username) {
    let base = (username || 'user').toString();
    let uname = base.slice(0, 30);
    let i = 0;
    while (true) {
      const exists = await t.oneOrNone(`SELECT 1 FROM "Tenant" WHERE "Username"=$1`, [uname]);
      if (!exists) return uname;
      i += 1;
      uname = `${base.slice(0, 28)}${i}`.slice(0, 30);
    }
  }

  // ---------- middlewares ----------
  async function requireAuth(req, res, next) {
    try {
      const authHeader = req.headers.authorization || '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
      if (!token) return res.status(401).json({ error: 'MISSING_BEARER' });
      req.decoded = await admin.auth().verifyIdToken(token);
      next();
    } catch {
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

  // ─────────────────────────────────────────────────────────────
  // 1) สมัครผู้เช่า: เก็บคำขอ + รหัสผ่าน (hash หรือ plain ตาม config)
  // ─────────────────────────────────────────────────────────────
  router.post('/tenant/register', async (req, res) => {
    try {
      const b = req.body || {};
      const firstName = (b.firstName || '').trim();
      const lastName = (b.lastName || '').trim();
      const email = (b.email || '').toLowerCase().trim();
      const phone = (b.phone || '').trim();
      const citizenID = (b.citizenID || '').trim();
      const username = (b.username || null);
      const roomNumber = (b.roomNumber || '').toString().trim().toUpperCase();
      const password = (b.password || '').toString();

      if (!firstName || !lastName || !email || !roomNumber || !password) {
        return res.status(400).json({ error: 'MISSING_FIELDS' });
      }
      if (password.length < 6) {
        return res.status(400).json({ error: 'PASSWORD_TOO_SHORT' });
      }

      // ✅ เก็บรหัสผ่าน (แบบ plain) ลง payload เพื่อใช้ตอน approve
      const payload = {
        firstName, lastName, email, phone, citizenID, username, roomNumber,
        passwordPlain: password
      };

      const ap = await db.one(`
      INSERT INTO "TenantApproval"
        ("TenantID","RoomNumber","FullName","Email","Status","Reason","RequestDate","ApprovedAt","ApprovedBy","Payload")
      VALUES
        (NULL,$1,$2,$3,'pending',NULL,NOW(),NULL,NULL,$4::jsonb)
      RETURNING "ApprovalID"
    `, [roomNumber, `${firstName} ${lastName}`.trim(), email, JSON.stringify(payload)]);

      return res.status(201).json({ ok: true, status: 'pending', approvalId: ap.ApprovalID });
    } catch (e) {
      console.error('POST /tenant/register error', e);
      return res.status(500).json({ error: 'REGISTER_FAILED' });
    }
  });


  // ─────────────────────────────────────────────────────────────
  // 2) สมัครเจ้าของ (เหมือนเดิม / เก็บ Password เป็น placeholder)
  // ─────────────────────────────────────────────────────────────
  async function createOrGetFirebaseUser({ email, password, displayName }) {
    try {
      const existing = await admin.auth().getUserByEmail(email);
      return existing;
    } catch (_) { }
    const created = await admin.auth().createUser({ email, password, displayName });
    return created;
  }

  router.post('/owner/register', async (req, res) => {
    const b = req.body || {};
    if (!required(b, ['firstName', 'lastName', 'email', 'phone', 'citizenId', 'password'])) {
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

  // ─────────────────────────────────────────────────────────────
  // 3) map uid -> role/id
  // ─────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────
  // 4) เช็กสถานะใบสมัครด้วยอีเมล (สำหรับหน้า Login)
  // ─────────────────────────────────────────────────────────────
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
      return res.json({
        approvalId: row.ApprovalID,
        status: String(row.Status || 'pending').toLowerCase(),
        reason: row.Reason || null
      });
    } catch (e) {
      console.error('GET /tenant-approval/status-by-email error', e);
      return res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ─────────────────────────────────────────────────────────────
  // 5) อนุมัติใบสมัคร: ใช้รหัสผ่านจากคำขอ และเขียนลง Tenant.Password
  // ─────────────────────────────────────────────────────────────
  router.post('/owner/approvals/:approvalId/approve', requireAuth, requireOwner, async (req, res) => {
    const { approvalId } = req.params;
    try {
      const out = await db.tx(async t => {
        // 5.1 ล็อกใบสมัคร
        const ap = await t.oneOrNone(
          `SELECT * FROM "TenantApproval" WHERE "ApprovalID"=$1 FOR UPDATE`, [approvalId]
        );
        if (!ap) return { status: 404, body: { error: 'NOT_FOUND' } };
        if (String(ap.Status || '').toLowerCase() !== 'pending') {
          return { status: 400, body: { error: 'NOT_PENDING' } };
        }

        const p = ap.Payload || {};
        const firstName = (p.firstName || (ap.FullName || '').split(' ')[0] || '').trim();
        const lastName = (p.lastName || (ap.FullName || '').split(' ').slice(1).join(' ') || '').trim();
        const email = (ap.Email || p.email || '').toLowerCase().trim();
        const roomNumber = (p.roomNumber || ap.RoomNumber || '').toString().trim().toUpperCase();
        const passwordPlain = (p.passwordPlain || p.password || '').toString();
        if (!firstName || !lastName || !email || !roomNumber) {
          return { status: 400, body: { error: 'MISSING_FIELDS' } };
        }

        // 5.2 รหัสผ่านจาก payload
        const passwordPlainInPayload = (p.passwordPlain || p.password || '').toString();
        const passwordHashInPayload = p.passwordHash || (passwordPlainInPayload
          ? await bcrypt.hash(passwordPlainInPayload, 10)
          : null);

        // เลือกค่าที่จะเก็บใน DB / ใช้สร้างผู้ใช้ Firebase
        const dbPassword = passwordPlain || 'NOT_STORED_IN_DB';

        const firebasePassword = passwordPlain || genTempPassword();
        // 5.3 เตรียม username/ข้อมูลอื่น
        const citizenID = normalizeNotNull(p.citizenID, '-');
        const phone = normalizeNotNull(p.phone, '-');
        let username = (p.username ?? '').toString().trim();

        // 5.4 สร้าง/รีใช้ Firebase user
        let firebaseUID = p.firebaseUID || null;
        if (!firebaseUID) {
          try {
            const fbUser = await admin.auth().createUser({
              email,
              password: firebasePassword,
              displayName: `${firstName} ${lastName}`.trim()
            });
            firebaseUID = fbUser.uid;
          } catch (err) {
            if (err.code === 'auth/email-already-exists' || err.errorInfo?.code === 'auth/email-already-exists') {
              const existing = await admin.auth().getUserByEmail(email);
              firebaseUID = existing.uid;
              // ถ้ามีรหัสผ่านใน payload ก็อัปเดตให้ตรง (ออปชัน)
              if (passwordPlain) {
                await admin.auth().updateUser(existing.uid, { password: firebasePassword });
              }
              if (existing.disabled) await admin.auth().updateUser(existing.uid, { disabled: false });
            } else {
              throw err;
            }
          }
        }

        // 5.5 กันซ้ำใน Tenant
        const dup = await t.oneOrNone(`
          SELECT "TenantID" FROM "Tenant"
          WHERE LOWER("Email")=$1 OR ("FirebaseUID" IS NOT NULL AND "FirebaseUID"=$2)
        `, [email, firebaseUID]);

        let tenantId;
        if (dup) {
          tenantId = dup.TenantID;
          await t.none(`
    UPDATE "Tenant"
    SET "Password"=$1, "RoomNumber"=$2
    WHERE "TenantID"=$3
  `, [passwordPlain || 'NOT_STORED_IN_DB', roomNumber, tenantId]);
        } else {
          if (!username) {
            const base = makeUsernameBase(email, roomNumber, firstName);
            username = await ensureUniqueUsername(t, base);
          } else {
            const exu = await t.oneOrNone(`SELECT 1 FROM "Tenant" WHERE "Username"=$1`, [username]);
            if (exu) username = await ensureUniqueUsername(t, username);
          }

          const tenant = await t.one(`
  INSERT INTO "Tenant"
    ("FirstName","LastName","CitizenID","BirthDate","Email","Phone",
     "Username","Password","RoomNumber","Start","End","ProfileImage",
     "Role","FirebaseUID","Status","ApprovedAt","ApprovedByOwnerID")
  VALUES
    ($1,$2,$3,NULL,$4,$5,$6,$7,$8,NULL,NULL,NULL,
     'tenant',$9,'approved',NOW(),$10)
  RETURNING "TenantID","FirebaseUID"
`, [firstName, lastName, citizenID, email, phone, username, dbPassword, roomNumber, firebaseUID, req.owner.id]);
          tenantId = tenant.TenantID;
        }

        // 5.6 ตั้ง claims
        if (firebaseUID) {
          await admin.auth().setCustomUserClaims(firebaseUID, {
            role: 'tenant',
            approved: true,
            tenantId: Number(tenantId),
          });
        }

        // 5.7 อัปเดตใบสมัคร & ห้อง
        await t.none(`
          UPDATE "TenantApproval"
          SET "Status"='approved', "ApprovedAt"=NOW(), "ApprovedBy"=$1, "TenantID"=$2
          WHERE "ApprovalID"=$3
        `, [req.owner.id, tenantId, approvalId]);

        await t.none(`
          UPDATE "Room"
          SET "Status"='occupied',
              "CurrentTenantID"=$2,
              "UpdatedAt"=NOW()
          WHERE "RoomNumber"=$1
        `, [roomNumber, tenantId]);

        return { status: 200, body: { ok: true, tenantId } };
      });

      return res.status(out.status).json(out.body);
    } catch (e) {
      console.error('POST /owner/approvals/:approvalId/approve error', e);
      res.status(500).json({ error: 'APPROVE_FAILED' });
    }
  });

  // ─────────────────────────────────────────────────────────────
  // 6) ปฏิเสธใบสมัคร
  // ─────────────────────────────────────────────────────────────
  router.post('/owner/approvals/:approvalId/reject', requireAuth, requireOwner, async (req, res) => {
    const { approvalId } = req.params;
    const reason = (req.body?.reason || '').toString().trim() || null;

    try {
      const out = await db.tx(async t => {
        const ap = await t.oneOrNone(
          `SELECT * FROM "TenantApproval" WHERE "ApprovalID"=$1 FOR UPDATE`, [approvalId]
        );
        if (!ap) return { status: 404, body: { error: 'NOT_FOUND' } };
        if (String(ap.Status || '').toLowerCase() !== 'pending') {
          return { status: 400, body: { error: 'NOT_PENDING' } };
        }

        await t.none(`
          UPDATE "TenantApproval"
          SET "Status"='rejected', "ApprovedAt"=NOW(), "ApprovedBy"=$1, "Reason"=$2
          WHERE "ApprovalID"=$3
        `, [req.owner.id, reason, approvalId]);

        const uid = ap.Payload?.firebaseUID;
        if (uid) {
          await admin.auth().setCustomUserClaims(uid, { role: 'tenant', approved: false });
        }

        return { status: 200, body: { ok: true } };
      });

      return res.status(out.status).json(out.body);
    } catch (e) {
      console.error('POST /owner/approvals/:approvalId/reject error', e);
      res.status(500).json({ error: 'REJECT_FAILED' });
    }
  });

  return router;
};
