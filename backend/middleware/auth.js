// middleware/auth.js
const admin = require('firebase-admin');

module.exports = (db) => async (req, res, next) => {
  const h = req.headers.authorization || '';
  const m = h.match(/^Bearer (.+)$/);
  if (!m) return res.status(401).json({ error: 'MISSING_BEARER' });

  try {
    const decoded = await admin.auth().verifyIdToken(m[1]);

    // NOTE: ปรับให้ตรงตารางของคุณ (เคยใช้ UserMap/หรือ Users)
    const u = await db.oneOrNone(`
      SELECT role,
             "TenantID" AS "tenantId",
             "OwnerID"  AS "ownerId"
      FROM "UserMap"
      WHERE uid=$1
    `, [decoded.uid]);

    if (!u) return res.status(403).json({ error: 'NO_LOCAL_ACCOUNT' });

    req.user = {
      uid: decoded.uid,
      email: decoded.email || null,
      role: u.role,                    // 'tenant' | 'owner' | 'admin'
      tenantId: u.tenantId || null,
      ownerId:  u.ownerId  || null,
    };
    next();
  } catch (e) {
    console.error('auth error', e);
    return res.status(401).json({ error: 'INVALID_TOKEN' });
  }
};
