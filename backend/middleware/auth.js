// backend/middleware/auth.js
require('dotenv').config();
const { verifyFirebaseIdToken } = require('../auth/verifyFirebaseToken');

function getBearer(req) {
  const h = req.headers.authorization || '';
  const [scheme, token] = h.split(' ');
  if (scheme?.toLowerCase() === 'bearer' && token) return token;
  return null;
}

// NOTE: findUserByUID ด้านล่างเป็นเวอร์ชันย่อย
// ถ้าคุณมีฟังก์ชันนี้อยู่แล้วที่อื่น ให้ import มาใช้แทนได้
async function findUserByUID(db, uid) {
  let row = await db.oneOrNone(
    `SELECT 'tenant' AS role, "TenantID" AS id FROM "Tenant" WHERE "FirebaseUID"=$1`, [uid]);
  if (row) return row;
  row = await db.oneOrNone(
    `SELECT 'owner'  AS role, "OwnerID" AS id FROM "Owner"  WHERE "FirebaseUID"=$1`, [uid]);
  if (row) return row;
  row = await db.oneOrNone(
    `SELECT 'admin'  AS role, "AdminID" AS id FROM "Admin"  WHERE "FirebaseUID"=$1`, [uid]);
  if (row) return row;
  return null;
}

module.exports = (db, options = {}) => {
  const { requireRole } = options;
  const projectId = process.env.FIREBASE_PROJECT_ID;

  return async (req, res, next) => {
    try {
      const idToken = getBearer(req) || req.body?.idToken || req.query?.idToken;
      if (!idToken) return res.status(401).json({ error: 'Missing ID token' });

      const payload = await verifyFirebaseIdToken(idToken, projectId);
      const uid = payload.user_id || payload.sub;

      const user = await findUserByUID(db, uid);
      if (!user) return res.status(404).json({ error: 'User not found in DB' });

      req.auth = { uid, role: user.role, id: user.id };
      if (requireRole && user.role !== requireRole) {
        return res.status(403).json({ error: 'Forbidden: wrong role' });
      }
      next();
    } catch (err) {
      console.error('Auth middleware error:', err);
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
  };

};

// backend/middleware/auth.js
module.exports = (db, options = {}) => {
  const { requireRole } = options;
  const projectId = process.env.FIREBASE_PROJECT_ID;

  return async (req, res, next) => {
    try {
      const idToken = (req.headers.authorization || '').split(' ')[1] || req.body?.idToken || req.query?.idToken;
      if (!idToken) return res.status(401).json({ error: 'Missing ID token' });

      const payload = await verifyFirebaseIdToken(idToken, projectId);
      const uid = payload.user_id || payload.sub;

      // หา role/id ตามเดิม
      const user = await findUserByUID(db, uid);
      if (!user) return res.status(404).json({ error: 'User not found in DB' });

      // ✅ ถ้าต้องเป็น tenant ให้เช็ค Status ด้วย
      if (requireRole === 'tenant') {
        const st = await db.oneOrNone(`SELECT "Status" FROM "Tenant" WHERE "FirebaseUID"=$1`, [uid]);
        if (!st || st.Status !== 'approved') {
          return res.status(403).json({ error: 'Account not approved yet' });
        }
      }

      if (requireRole && user.role !== requireRole) {
        return res.status(403).json({ error: 'Forbidden: wrong role' });
      }

      req.auth = { uid, role: user.role, id: user.id };
      next();
    } catch (err) {
      console.error('Auth middleware error:', err);
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
  };
};

