// backend/auth/verifyFirebaseToken.js
const { createRemoteJWKSet, jwtVerify } = require('jose');

// URL ของ JWKS สำหรับ Firebase ID Token
const JWKS_URL = new URL(
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'
);

/**
 * ตรวจสอบ Firebase ID Token โดยไม่ใช้ firebase-admin
 * @param {string} idToken - JWT จาก Firebase Auth
 * @param {string} projectId - Firebase project id (เช่น my-app-123)
 * @returns {Promise<object>} - payload ของ token (claims)
 */
async function verifyFirebaseIdToken(idToken, projectId) {
  if (!projectId) {
    throw new Error('Missing projectId (FIREBASE_PROJECT_ID)');
  }

  // ตามสเปคของ Firebase ID Token:
  // iss = https://securetoken.google.com/<projectId>
  // aud = <projectId>
  const issuer = `https://securetoken.google.com/${projectId}`;
  const audience = projectId;

  // jose จะดึงและแคช JWKS ให้อัตโนมัติ
  const JWKS = createRemoteJWKSet(JWKS_URL);

  const { payload } = await jwtVerify(idToken, JWKS, {
    issuer,
    audience,
  });

  // ตัวสำคัญ: uid อยู่ใน sub/user_id
  const uid = payload.user_id || payload.sub;
  if (!uid) {
    throw new Error('Invalid token: no uid found');
  }

  return payload; // มี fields: sub/user_id, email, exp, auth_time, etc.
}

module.exports = { verifyFirebaseIdToken };
