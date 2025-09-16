const path = require('path');
const fs = require('fs');
require('dotenv').config();                    // <-- ต้องมี

const express = require('express');
const cors = require('cors');
const cookieParser = require('cookie-parser');
const pgp = require('pg-promise')();

const auth = require('./middleware/auth');

const app = express();                         // <-- ต้องประกาศก่อนใช้ app.use

// ---------- Firebase Admin ----------
const admin = require('firebase-admin');

const saPath = path.join(__dirname, 'firebase-service-account.json');
if (fs.existsSync(saPath)) {
  const serviceAccount = require(saPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id,
  });
  console.log('✅ Firebase Admin initialized with Service Account.');
} else {
  // ใช้ ADC แต่ "ต้อง" ระบุ projectId ผ่าน env
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: process.env.FIREBASE_PROJECT_ID,  // <-- ต้องมีค่า
  });
  console.warn('⚠️ SA not found. Using ADC. projectId=%s', process.env.FIREBASE_PROJECT_ID);
}

// ---------- CORS / JSON / Cookies ----------
app.use(cors({
  origin: process.env.CORS_ORIGIN ? process.env.CORS_ORIGIN.split(',') : true,
  credentials: true,
}));
app.use(express.json());
app.use(cookieParser());

// ---------- Health ----------
app.get('/ping', (_req, res) => res.send('pong'));
app.get('/health', (_req, res) => res.json({ ok: true, t: new Date().toISOString() }));

// ---------- DB ----------
const db = pgp({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'MyDorm',
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
});
db.connect()
  .then(obj => { console.log('✅ Connected to PostgreSQL'); obj.done(); })
  .catch(err => { console.error('❌ Cannot connect to database:', err); });

// (… โค้ดส่วนถัดไปของคุณค่อยตามมา …)

// ---- Tuya ----
const { TuyaContext } = require('@tuya/tuya-connector-nodejs');
const tuya = new TuyaContext({
  baseUrl: process.env.TUYA_BASE_URL,
  accessKey: process.env.TUYA_ACCESS_ID,
  accessSecret: process.env.TUYA_ACCESS_SECRET,
});

// ---- Static uploads ----
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

const registerRoutes = require('./routes/register');
app.use('/api', registerRoutes(db, admin));

async function findUserByUID(db, uid) {
  let row = await db.oneOrNone(
    `SELECT 'tenant' AS role, "TenantID" AS id, "Email","FirstName","LastName"
     FROM "Tenant" WHERE "FirebaseUID"=$1`, [uid]);
  if (row) return row;

  row = await db.oneOrNone(
    `SELECT 'owner' AS role, "OwnerID" AS id, "Email","FirstName","LastName"
     FROM "Owner" WHERE "FirebaseUID"=$1`, [uid]);
  if (row) return row;

  row = await db.oneOrNone(
    `SELECT 'admin' AS role, "AdminID" AS id, "Email","FirstName","LastName"
     FROM "Admin" WHERE "FirebaseUID"=$1`, [uid]);
  if (row) return row;

  return null;
}

app.post('/api/login', async (req, res) => {
  const { idToken } = req.body;
  if (!idToken) return res.status(400).json({ message: 'ไม่พบ ID Token' });

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    const uid = decoded.uid || decoded.user_id || decoded.sub;
    const email = decoded.email || null;

    // 1) มีใน Tenant แล้ว -> ปกติ
    const user = await findUserByUID(db, uid);
    if (user) {
      return res.json({ message: 'Login สำเร็จ', uid, role: user.role, id: user.id });
    }

    // 2) ยังไม่มี -> เช็คใน TenantApproval
    const row = await db.oneOrNone(`
  SELECT "ApprovalID","Status"
  FROM "TenantApproval"
  WHERE ((("Payload")::jsonb->>'firebaseUID') = $1) OR "Email" = $2
  ORDER BY "ApprovalID" DESC
  LIMIT 1
`, [uid, email]);

    if (ap) {
      return res.json({
        message: 'Login สำเร็จ (pending)',
        uid,
        role: 'tenant',
        status: String(ap.Status || 'pending').toLowerCase(),
        approvalId: ap.ApprovalID
      });
    }

    // ไม่พบทั้งสองที่
    return res.status(404).json({ message: 'ไม่พบข้อมูลผู้ใช้ในระบบ' });
  } catch (error) {
    console.error('Error in /api/login:', error);
    return res.status(401).json({ message: 'ID Token ไม่ถูกต้องหรือหมดอายุ' });
  }
});


// ===== Auth helpers (เพิ่มไว้ด้านล่าง login route ก็ได้) =====
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

const approvalsRoutes = require('./routes/approvals');
app.use('/api', approvalsRoutes(db, admin, requireAuth, requireOwner));

// ---- รวมทุก routes เป็น bundle ตามโมดูล ----
const ownerBundle = require('./routes/owner');   // <-- ต้องมี routes/owner/index.js
app.use('/api', ownerBundle(db, tuya));

const tenantBundle = require('./routes/tenant');  // <-- ต้องมี routes/tenant/index.js
app.use('/api', tenantBundle(db));


// ---- ตัวอย่าง Protected (ของเดิม) ----
app.get('/api/wallet', auth(db, { requireRole: 'tenant' }), async (req, res) => {
  const tenantId = req.auth.id;
  const row = await db.oneOrNone(`SELECT * FROM "Wallet" WHERE "TenantID"=$1`, [tenantId]);
  if (!row) {
    const created = await db.one(
      `INSERT INTO "Wallet" ("TenantID","Balance") VALUES ($1,0) RETURNING *`, [tenantId]
    );
    return res.status(201).json(created);
  }
  res.json(row);
});


// ---- 404 + Error handler (ช่วย debug เร็ว) ----
app.use((req, res) => {
  console.warn('404 Not Found:', req.method, req.originalUrl);
  res.status(404).json({ error: 'NOT_FOUND', path: req.originalUrl });
});
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'INTERNAL_ERROR', message: err.message });
});

// ---- Boot ----
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';
app.listen(PORT, HOST, () => {
  console.log(`Server running at http://${HOST}:${PORT}`);
});

