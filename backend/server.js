// server.js — clean & structured

// -----------------------------------------------------------------------------
// 0) Bootstrap
// -----------------------------------------------------------------------------
require('dotenv').config();
const path = require('path');
const fs = require('fs');

const express = require('express');
const cors = require('cors');
const cookieParser = require('cookie-parser');
const admin = require('firebase-admin');

const app = express();
process.on('unhandledRejection', e => console.error('[UNHANDLED REJECTION]', e));
process.on('uncaughtException', e => console.error('[UNCAUGHT]', e));

// -----------------------------------------------------------------------------
// 1) Debug/Logging Utilities
// -----------------------------------------------------------------------------
const DEBUG_VERBOSE = String(process.env.DEBUG_VERBOSE || 'true').toLowerCase() === 'true';
const DB_SLOW_MS = Number(process.env.DB_SLOW_MS || 800);
const REQUEST_TIMEOUT_MS = Number(process.env.REQUEST_TIMEOUT_MS || 30000);

const LAST_ERRORS = [];
function pushErr(kind, msg, ctx = {}) {
  LAST_ERRORS.push({ ts: new Date().toISOString(), kind, msg: String(msg || ''), ctx });
  if (LAST_ERRORS.length > 200) LAST_ERRORS.shift();
  if (DEBUG_VERBOSE) console.warn('[DBG]', kind, msg, ctx);
}

// simple router tracer
function wrap(label, router) {
  const r = express.Router();
  r.use((req, res, next) => {
    const t0 = Date.now();
    console.log(`[HIT ${label}] ${req.method} ${req.baseUrl}${req.path}`);
    res.on('finish', () => {
      console.log(`[DONE ${label}] ${req.method} ${req.baseUrl}${req.path} -> ${res.statusCode} in ${Date.now() - t0}ms`);
    });
    next();
  });
  r.use(router);
  return r;
}

// กันยิงระหว่างบู๊ต
let BOOTING = true;
setTimeout(() => { BOOTING = false; }, 2000);
app.use((req, res, next) => {
  if (BOOTING && req.path.startsWith('/api/')) {
    return res.status(503).json({ error: 'BOOTING' });
  }
  next();
});

// -----------------------------------------------------------------------------
// 2) PG-Promise (with safe instrumentation)
// -----------------------------------------------------------------------------
const initOptions = {
  connect: async (e) => {
    try {
      await e.client.query(`SET search_path TO public`);
      await e.client.query(`SET statement_timeout = '5000ms'`);
      await e.client.query(`SET idle_in_transaction_session_timeout = '5000ms'`);
      await e.client.query(`SET lock_timeout = '4000ms'`);
    } catch (err) {
      pushErr('DB_CONNECT_SETUP_FAIL', err.message);
    }
    if (DEBUG_VERBOSE) console.log('[DB] CONNECT', e?.client?.processID);
  },
  disconnect: (e) => { if (DEBUG_VERBOSE) console.log('[DB] DISCONNECT', e?.client?.processID); },
  query: (e) => {
    if (e) e.__started = Date.now();
    if (!DEBUG_VERBOSE) return;
    try {
      const sql = (e?.query || '').replace(/\s+/g, ' ').trim().slice(0, 300);
      const params = e?.params ? JSON.stringify(e.params).slice(0, 300) : '';
      console.log(`[DB] ▶ ${sql}${params ? ' | ' + params : ''}`);
    } catch { }
  },
  receive: (rows, _result, e) => {
    const started = e && typeof e.__started === 'number' ? e.__started : Date.now();
    const dur = Date.now() - started;
    if (dur >= DB_SLOW_MS) console.warn(`[DB] ◀ SLOW ${dur}ms rows=${rows?.length ?? 0}`);
    else if (DEBUG_VERBOSE) console.log(`[DB] ◀ ${dur}ms rows=${rows?.length ?? 0}`);
  },
  error: (err, e) => {
    const dur = e && typeof e.__started === 'number' ? (Date.now() - e.__started) : null;
    const sql = ((e && e.query) ? e.query : '').toString().replace(/\s+/g, ' ').trim().slice(0, 300);
    pushErr('DB_ERROR', err?.message || String(err), { dur, sql, params: e?.params });
  }
};
const pgp = require('pg-promise')(initOptions);
const SAFE_MODE = String(process.env.SAFE_MODE || 'false').toLowerCase() === 'true';

// Global PG defaults
pgp.pg.defaults.statement_timeout = 15000;
pgp.pg.defaults.query_timeout = 15000;
pgp.pg.defaults.connectionTimeoutMillis = 5000;

// Create connection
const db = pgp({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'MyDorm',
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
  application_name: 'AppDorm',
  statement_timeout: 5000,
  query_timeout: 5000,
});

db.connect()
  .then(obj => { console.log('✅ Connected to PostgreSQL'); obj.done(); })
  .catch(err => { console.error('❌ Cannot connect to database:', err); });

// One-shot: indexes & guards
async function ensureDbPerformance(db) {
  console.log('🔧 Ensuring performance indexes + timeouts...');
  try {
    const ms = String(process.env.DB_STMT_TIMEOUT_MS || '8000') + 'ms';
    await db.none('SET statement_timeout = $1', [ms]);
  } catch (e) {
    console.warn('⚠️ SET statement_timeout failed:', e.message);
  }

  const sql = `
  CREATE INDEX IF NOT EXISTS idx_elec_room_at_desc ON "ElectricReading" ("RoomNumber", "At" DESC);
  CREATE INDEX IF NOT EXISTS idx_elec_dev_at_desc  ON "ElectricReading" ("DeviceID", "At" DESC);

  DO $$
  BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='TuyaDevice' AND column_name='building_id') THEN
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_tuya_room_build_active_iddesc
               ON "TuyaDevice" ("RoomNumber", COALESCE("Active",FALSE), building_id, id DESC)';
    ELSE
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_tuya_room_active_iddesc
               ON "TuyaDevice" ("RoomNumber", COALESCE("Active",FALSE), id DESC)';
    END IF;
  END$$;

  CREATE INDEX IF NOT EXISTS idx_room_build_room ON "Room" ("BuildingID", "RoomNumber");

  DO $$
  BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='Tenant' AND column_name='Start')
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='Tenant' AND column_name='End') THEN
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_tenant_room_start_end ON "Tenant" ("RoomNumber","Start","End")';
    ELSE
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_tenant_room ON "Tenant" ("RoomNumber")';
    END IF;
  END$$;

  DO $$
  DECLARE col text;
  BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='Payment' AND column_name='PaymentDate') THEN
      col := 'PaymentDate';
    ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='Payment' AND column_name='PaidAt') THEN
      col := 'PaidAt';
    END IF;

    IF col IS NOT NULL THEN
      EXECUTE format('CREATE INDEX IF NOT EXISTS idx_payment_%I_only ON "Payment" (%I)', lower(col), col);
      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='Payment' AND column_name='BuildingID') THEN
        EXECUTE format('CREATE INDEX IF NOT EXISTS idx_payment_%I_build ON "Payment" (%I, "BuildingID")', lower(col), col);
      END IF;
      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='Payment' AND column_name='TenantID') THEN
        EXECUTE format('CREATE INDEX IF NOT EXISTS idx_payment_%I_tenant ON "Payment" (%I, "TenantID")', lower(col), col);
      END IF;
    END IF;
  END$$;
  `;
  try {
    await db.none(sql);
    console.log('✅ Index ensured');
  } catch (e) {
    console.warn('⚠️ Skipped some indexes:', e.message);
  }
}
ensureDbPerformance(db).catch(e => console.warn('bootstrap warn:', e.message));

// -----------------------------------------------------------------------------
// 3) Core Middlewares
// -----------------------------------------------------------------------------
const corsOpts = {
  origin: (origin, cb) => {
    if (!origin) return cb(null, true);
    const ok =
      /^http:\/\/(localhost|127\.0\.0\.1):\d+$/i.test(origin) ||
      /^http:\/\/192\.168\.\d{1,3}\.\d{1,3}(:\d+)?$/i.test(origin) ||
      (process.env.CORS_ORIGIN || '').split(',').map(s => s.trim()).filter(Boolean).includes(origin);
    cb(null, ok);
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Accept'],
  credentials: true,
  optionsSuccessStatus: 204,
};
app.use(cors(corsOpts));
app.options(/^\/api\/.*$/, cors(corsOpts));

app.use(express.json({ limit: '5mb' }));
app.use(cookieParser());

// per-response timeout
app.use((req, res, next) => { res.setTimeout(30000); next(); });

// Global request timeout watchdog
app.use((req, res, next) => {
  const started = Date.now();
  const t = setTimeout(() => {
    if (!res.headersSent) {
      console.warn('[TIMEOUT]', req.method, req.originalUrl, 'after', Date.now() - started, 'ms');
      res.status(504).json({ error: 'REQUEST_TIMEOUT' });
    }
  }, REQUEST_TIMEOUT_MS);
  res.on('finish', () => clearTimeout(t));
  res.on('close', () => clearTimeout(t));
  next();
});

// Preflight log
app.use((req, res, next) => {
  if (req.method === 'OPTIONS') {
    console.log('[CORS] OPTIONS', req.path, '| ACR-Method =', req.headers['access-control-request-method'], '| ACR-Headers =', req.headers['access-control-request-headers']);
    const origin = req.headers.origin || '*';
    res.header('Access-Control-Allow-Origin', origin);
    res.header('Vary', 'Origin');
    res.header('Access-Control-Allow-Credentials', 'true');
    res.header('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
    res.header('Access-Control-Allow-Headers', req.headers['access-control-request-headers'] || 'Authorization,Content-Type,Accept');
    return res.sendStatus(204);
  }
  next();
});

// Basic access logs
app.use((req, _res, next) => {
  if (req.path.startsWith('/api/')) {
    console.log('[IN]', req.method, req.originalUrl, '| Origin =', req.headers.origin || '(none)');
  }
  next();
});

// Promote idToken → Authorization
app.use('/api', (req, _res, next) => {
  if (!req.headers.authorization) {
    const idToken = req.query?.idToken || req.body?.idToken;
    if (idToken) req.headers.authorization = `Bearer ${idToken}`;
  }
  next();
});

// Static uploads (no-cache)
app.use('/uploads', express.static(path.join(__dirname, 'uploads'), {
  etag: false, lastModified: false, cacheControl: false,
  setHeaders: (res) => {
    res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.set('Pragma', 'no-cache');
    res.set('Expires', '0');
  }
}));

// -----------------------------------------------------------------------------
// 4) Firebase Admin
// -----------------------------------------------------------------------------
const saPath = path.join(__dirname, 'firebase-service-account.json');
if (fs.existsSync(saPath)) {
  const serviceAccount = require(saPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id,
  });
  console.log('✅ Firebase Admin initialized with Service Account.');
} else {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: process.env.FIREBASE_PROJECT_ID,
  });
  console.warn('⚠️ SA not found. Using ADC. projectId=%s', process.env.FIREBASE_PROJECT_ID);
}

// -----------------------------------------------------------------------------
// 5) Health & Debug endpoints
// -----------------------------------------------------------------------------
app.get('/ping', (_req, res) => res.send('pong'));
app.get('/health', (_req, res) => res.json({ ok: true, t: new Date().toISOString() }));

app.get('/api/_debug/tuya', (_req, res) => {
  const mask = v => (v ? v.slice(0, 2) + '***' + v.slice(-2) : '(empty)');
  const { buildTuyaContextWithDebug } = require('./utils/tuyaSafe');
  const tuyaTmp = buildTuyaContextWithDebug('server');
  res.json({
    baseUrl: (process.env.TUYA_BASE_URL || '').trim() || '(empty)',
    accessIdSource: process.env.TUYA_ACCESS_ID ? 'TUYA_ACCESS_ID' : process.env.TUYA_AK ? 'TUYA_AK' : 'none',
    accessSecretSource: process.env.TUYA_ACCESS_SECRET ? 'TUYA_ACCESS_SECRET' : process.env.TUYA_SK ? 'TUYA_SK' : 'none',
    maskedAccessId: mask(process.env.TUYA_ACCESS_ID || process.env.TUYA_AK),
    maskedAccessSecret: mask(process.env.TUYA_ACCESS_SECRET || process.env.TUYA_SK),
    clientKind: tuyaTmp.__kind || 'REAL_TUYA',
    clientSource: tuyaTmp.__source || 'server',
  });
});

app.get('/api/_debug/db-scan', async (_req, res) => {
  try {
    const uid = 'ryHu5A1RWpWRNAHUWubtCKKHxqE2';
    const counts = await db.one(`
      SELECT
        (SELECT COUNT(*) FROM "Owner")::int    AS owners,
        (SELECT COUNT(*) FROM "Building")::int AS buildings,
        (SELECT COUNT(*) FROM "Room")::int     AS rooms,
        (SELECT COUNT(*) FROM "Tenant")::int   AS tenants
    `);
    const ownerByUid = await db.oneOrNone(`SELECT "OwnerID","Email" FROM "Owner" WHERE "FirebaseUID"=$1`, [uid]);
    const sampleOwners = await db.any(`SELECT "OwnerID","Email" FROM "Owner" ORDER BY "OwnerID" LIMIT 5`);
    const sampleBuildings = await db.any(`SELECT "BuildingID","BuildingName","OwnerID" FROM "Building" ORDER BY "BuildingID" LIMIT 5`);
    res.json({ db: { host: process.env.DB_HOST, db: process.env.DB_NAME || 'MyDorm' }, counts, ownerByUid, sampleOwners, sampleBuildings });
  } catch (e) {
    console.error('db-scan error:', e);
    res.status(500).json({ error: 'DB_SCAN_FAIL', message: e.message });
  }
});

// -----------------------------------------------------------------------------
// 6) Auth helpers
// -----------------------------------------------------------------------------
function withTimeout(promise, ms, label) {
  return Promise.race([
    promise,
    new Promise((_, rej) => setTimeout(() => rej(new Error(`TIMEOUT_${label}_${ms}ms`)), ms)),
  ]);
}

async function requireAuth(req, res, next) {
  try {
    const h = req.headers.authorization || '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : null;
    if (!token) return res.status(401).json({ error: 'MISSING_BEARER' });
    console.time('[AUTH] verifyIdToken');
    req.decoded = await withTimeout(admin.auth().verifyIdToken(token), 5000, 'verifyIdToken');
    console.timeEnd('[AUTH] verifyIdToken');
    next();
  } catch (e) {
    console.error('[AUTH] ERROR:', e.message || e);
    return res.status(401).json({ error: 'INVALID_TOKEN_OR_TIMEOUT' });
  }
}

async function requireOwner(req, res, next) {
  try {
    const uid = req.decoded.uid || req.decoded.user_id || req.decoded.sub;
    const owner = await db.oneOrNone(`SELECT "OwnerID" AS id FROM "Owner" WHERE "FirebaseUID"=$1`, [uid]);
    if (!owner) return res.status(403).json({ error: 'NOT_OWNER' });
    req.owner = owner;
    next();
  } catch (e) {
    console.error('requireOwner error:', e);
    return res.status(500).json({ error: 'OWNER_LOOKUP_FAILED' });
  }
}

// helpers for /api/buildings alias
function bearerFrom(req) {
  const raw = req.headers.authorization || '';
  const low = raw.toLowerCase();
  if (low.startsWith('bearer ')) return raw.slice(7);
  return req.query.idToken || req.body?.idToken || null;
}
async function getOwnerIdFromReq(req) {
  if (req.params?.ownerId) return Number(req.params.ownerId);
  if (req.query?.ownerId) return Number(req.query.ownerId);
  const token = bearerFrom(req);
  if (!token) return null;
  const decoded = await withTimeout(admin.auth().verifyIdToken(token), 5000, 'verifyIdToken');
  const uid = decoded.uid || decoded.user_id || decoded.sub;
  const row = await db.oneOrNone(`SELECT "OwnerID" AS id FROM "Owner" WHERE "FirebaseUID"=$1`, [uid]);
  return row?.id || null;
}

// -----------------------------------------------------------------------------
// 7) Login & Route Aliases
// -----------------------------------------------------------------------------
const registerRoutes = require('./routes/register');
app.use('/api', registerRoutes(db, admin));

async function findUserByUID(db, uid) {
  let row = await db.oneOrNone(`SELECT 'tenant' AS role, "TenantID" AS id, "Email","FirstName","LastName" FROM "Tenant" WHERE "FirebaseUID"=$1`, [uid]);
  if (row) return row;
  row = await db.oneOrNone(`SELECT 'owner'  AS role, "OwnerID"  AS id, "Email","FirstName","LastName" FROM "Owner" WHERE "FirebaseUID"=$1`, [uid]);
  if (row) return row;
  row = await db.oneOrNone(`SELECT 'admin'  AS role, "AdminID"  AS id, "Email","FirstName","LastName" FROM "Admin" WHERE "FirebaseUID"=$1`, [uid]);
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

    const user = await findUserByUID(db, uid);
    if (user) return res.json({ message: 'Login สำเร็จ', uid, role: user.role, id: user.id });

    const ap = await db.oneOrNone(`
      SELECT "ApprovalID","Status"
      FROM "TenantApproval"
      WHERE ((("Payload")::jsonb->>'firebaseUID') = $1) OR "Email" = $2
      ORDER BY "ApprovalID" DESC
      LIMIT 1
    `, [uid, email]);

    if (ap) {
      return res.json({
        message: 'Login สำเร็จ (pending)',
        uid, role: 'tenant',
        status: String(ap.Status || 'pending').toLowerCase(),
        approvalId: ap.ApprovalID
      });
    }
    return res.status(404).json({ message: 'ไม่พบข้อมูลผู้ใช้ในระบบ' });
  } catch (error) {
    console.error('Error in /api/login:', error);
    return res.status(401).json({ message: 'ID Token ไม่ถูกต้องหรือหมดอายุ' });
  }
});

// alias: /api/buildings & /api/owners/:ownerId/buildings
async function buildingsHandler(req, res) {
  try {
    console.log('[ALIAS] HIT', req.method, req.originalUrl);
    const ownerId = await getOwnerIdFromReq(req);
    if (!ownerId) return res.status(400).json({ error: 'MISSING_OWNER_ID_OR_TOKEN' });
    const rows = await db.any(`
      SELECT "BuildingID" AS "buildingId","BuildingName" AS "buildingName","OwnerID" AS "ownerId",
             "Address" AS "address","Floors" AS "floors","Rooms" AS "rooms"
      FROM "Building" WHERE "OwnerID" = $1 ORDER BY "BuildingID"
    `, [ownerId]);
    res.json(rows);
  } catch (e) {
    if ((e?.message || '').startsWith('TIMEOUT_verifyIdToken')) {
      return res.status(401).json({ error: 'INVALID_TOKEN_OR_TIMEOUT' });
    }
    console.error('[ALIAS /buildings] ERROR:', e);
    res.status(500).json({ error: 'INTERNAL_ERROR' });
  }
}
app.get('/api/buildings', buildingsHandler);
app.get('/api/owners/:ownerId/buildings', buildingsHandler);

// legacy → new owner paths
app.all('/api/rooms/:buildingId', (req, res) => {
  const q = req._parsedUrl?.search || '';
  res.redirect(307, `/api/owner/rooms/${req.params.buildingId}${q}`);
});
app.all('/api/building/:id/monthly-income-summary', (req, res) => {
  const q = req._parsedUrl?.search || '';
  res.redirect(307, `/api/owner/building/${req.params.id}/monthly-income-summary${q}`);
});
app.all('/api/building/:id/tenants', (req, res) => {
  const q = req._parsedUrl?.search || '';
  res.redirect(307, `/api/owner/building/${req.params.id}/tenants${q}`);
});
app.all('/api/building/:id/tenant-count', (req, res) => {
  const q = req._parsedUrl?.search || '';
  res.redirect(307, `/api/owner/building/${req.params.id}/tenant-count${q}`);
});
app.all('/api/building/:id/monthly-income-detail', (req, res) => {
  const q = req._parsedUrl?.search || '';
  res.redirect(307, `/api/owner/building/${req.params.id}/monthly-income-detail${q}`);
});

// -----------------------------------------------------------------------------
// 8) Tuya + Bundled Routers (owner before tenant)
// -----------------------------------------------------------------------------
const { buildTuyaContextWithDebug } = require('./utils/tuyaSafe');
const tuya = buildTuyaContextWithDebug('server');

// SAFE_MODE: minimal owner endpoints (หลังมี db แล้วเท่านั้น)
if (SAFE_MODE) {
  const router = require('express').Router();

  router.get('/rooms/:buildingId', async (req, res) => {
    const bId = Number(req.params.buildingId);
    try {
      const rows = await db.any(`
        SELECT r."RoomNumber" AS "roomNumber",
               COALESCE(r."Status",'UNKNOWN') AS status,
               COALESCE(r."PricePerMonth",0)::float8 AS "pricePerMonth",
               r."BuildingID" AS "buildingId"
        FROM public."Room" r
        WHERE r."BuildingID" = $1::int
        ORDER BY r."RoomNumber" ASC
      `, [bId]);
      res.json(rows);
    } catch (e) { res.status(500).json({ error: 'SERVER_ERROR', detail: e.message }); }
  });

  router.get('/building/:id/tenant-count', async (req, res) => {
    const bId = Number(req.params.id);
    try {
      const row = await db.oneOrNone(`
        SELECT COUNT(*)::int AS count
        FROM public."Tenant" t
        JOIN public."Room" r ON r."RoomNumber" = t."RoomNumber"
        WHERE r."BuildingID"=$1::int
          AND COALESCE(t."Status",'') ILIKE 'active'
      `, [bId]);
      res.json({ count: row?.count || 0 });
    } catch (e) { res.status(500).json({ error: 'SERVER_ERROR', detail: e.message }); }
  });

  router.get('/building/:id/monthly-income-summary', async (req, res) => {
    const bId = Number(req.params.id);
    const months = Math.min(24, Math.max(1, Number(req.query.months || 12)));
    try {
      const rows = await db.any(`
        WITH m AS (SELECT generate_series(0, $2::int - 1) AS off),
        series AS (
          SELECT
            to_char(date_trunc('month', (date_trunc('month', CURRENT_DATE) - (off || ' months')::interval)), 'YYYY-MM') AS month_key,
            date_trunc('month', (date_trunc('month', CURRENT_DATE) - (off || ' months')::interval)) AS start_at,
            (date_trunc('month', (date_trunc('month', CURRENT_DATE) - (off || ' months')::interval)) + interval '1 month') AS end_at
          FROM m
        )
        SELECT s.month_key AS ym,
               COALESCE((
                 SELECT SUM(p."TotalAmount")::float8
                 FROM public."Room" r
                 JOIN public."Tenant" t  ON t."RoomNumber" = r."RoomNumber"
                 JOIN public."Payment" p ON p."TenantID"   = t."TenantID"
                 WHERE r."BuildingID" = $1::int
                   AND p."PaymentDate" >= s.start_at
                   AND p."PaymentDate" <  s.end_at
               ),0) AS total
        FROM series s
        ORDER BY s.start_at ASC
      `, [bId, months]);
      res.json({ months: rows });
    } catch (e) { res.status(500).json({ error: 'SERVER_ERROR', detail: e.message }); }
  });

  router.get('/building/:id/monthly-income-detail', async (req, res) => {
    const bId = Number(req.params.id);
    const y = Number(req.query.year), m = Number(req.query.month);
    try {
      const items = await db.any(`
        SELECT
          p."PaymentID" AS id,
          p."PaymentDate" AS "PaidAt",
          r."RoomNumber" AS "roomNumber",
          COALESCE(
           NULLIF(trim(COALESCE(tn."FirstName",'') || ' ' || COALESCE(tn."LastName",'')), ''),
            tn."Email",
            ''
          ) AS "PayerName",
          COALESCE(p."TotalAmount"::float8,0) AS "Amount",
          COALESCE(p."PaymentMethod",'') AS "Type"
        FROM public."Payment" p
        JOIN public."Tenant" tn ON tn."TenantID" = p."TenantID"
        JOIN public."Room"   r  ON r."RoomNumber" = tn."RoomNumber"
        WHERE r."BuildingID" = $1::int
          AND p."PaymentDate" >= make_date($2::int,$3::int,1)
          AND p."PaymentDate" <  (make_date($2::int,$3::int,1) + interval '1 month')
        ORDER BY p."PaymentDate" DESC
      `, [bId, y, m]);
      const total = items.reduce((s, r) => s + (Number(r.Amount) || 0), 0);
      res.json({ total, items });
    } catch (e) { res.status(500).json({ error: 'SERVER_ERROR', detail: e.message }); }
  });

  app.use('/api/owner', router);
}

// approvals (needs auth)
const approvalsRoutes = require('./routes/approvals');
app.use('/api', approvalsRoutes(db, admin, requireAuth, requireOwner));


// owner bundle (ส่ง middleware เข้า factory ให้ครบ)
const ownerBundle = require('./routes/owner/index.js');
app.use('/api/owner', wrap('owner', ownerBundle(db, requireAuth, requireOwner, tuya)));

// tenant bundle (no auth required here)
const tenantBundle = require('./routes/tenant');
app.use('/api', wrap('tenant', tenantBundle(db)));

// tuya control
const tuyaControl = require('./routes/tuyaControl');
app.use('/api/tuya', tuyaControl(db, tuya, requireAuth, requireOwner));

// -----------------------------------------------------------------------------
// 9) Schedulers (Electric Cron)
// -----------------------------------------------------------------------------
const createElectricCron = require('./schedulers/electric_hourly');
const cron = createElectricCron({ app, db, baseUrl: `http://127.0.0.1:${process.env.PORT || 3000}` });
const cronHandle = cron.start(); // eslint-disable-line no-unused-vars

app.post('/admin/electric-cron/run-now', (req, res) => {
  const sec = req.query.secret || '';
  if (!process.env.ELECTRIC_CRON_SECRET || sec !== process.env.ELECTRIC_CRON_SECRET) {
    return res.status(403).json({ ok: false, error: 'forbidden' });
  }
  cron.runOnce()
    .then(r => res.json(r))
    .catch(e => { console.error(e); res.status(500).json({ ok: false, error: String(e?.message || e) }); });
});

// -----------------------------------------------------------------------------
// 10) 404 & Error handler
// -----------------------------------------------------------------------------
app.use((req, res) => {
  console.warn('404 Not Found:', req.method, req.originalUrl);
  res.status(404).json({ error: 'NOT_FOUND', path: req.originalUrl });
});
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'INTERNAL_ERROR', message: err.message });
});

// -----------------------------------------------------------------------------
// 11) Boot
// -----------------------------------------------------------------------------
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';
app.listen(PORT, HOST, () => {
  console.log('✅ Tuya context init by [server] @', (process.env.TUYA_BASE_URL || '(env default)'));
  console.log('Server running at http://' + HOST + ':' + PORT);
});
