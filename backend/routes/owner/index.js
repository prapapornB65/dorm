// routes/owner/index.js
module.exports = (db, requireAuth, requireOwner, tuya) => {
  const express = require('express');
  const router = express.Router();

  router.get('/__ping', (req, res) => res.json({ ok: true, who: 'owner-bundle' }));

  // ---------- URL rewrite rules ----------
  router.use((req, _res, next) => {
    const rules = [
      { from: /^\/building\/(\d+)\/tenants(\?.*)?$/i,               to: '/building/$1/tenants$2' },
      { from: /^\/building\/(\d+)\/tenant-count(\?.*)?$/i,           to: '/building/$1/tenant-count$2' },
      { from: /^\/building\/(\d+)\/monthly-income-summary(\?.*)?$/i, to: '/building/$1/monthly-income-summary$2' },
      { from: /^\/building\/(\d+)\/monthly-income-detail(\?.*)?$/i,  to: '/building/$1/monthly-income-detail$2' },
    ];
    for (const r of rules) {
      if (r.from.test(req.url)) { req.url = req.url.replace(r.from, r.to); break; }
    }
    next();
  });

  // ---------- Route modules (ใส่ requireAuth + requireOwner ทุกอันที่เป็นของ owner) ----------
  router.use(require('./ownerApprovals')(db, requireAuth, requireOwner));
  router.use(require('./ownerAccount')(db)); // ไม่ต้อง auth
  router.use(require('./equipment')(db, requireAuth, requireOwner));
  router.use(require('./building')(db));     // ถ้าไฟล์นี้ต้องการ auth ให้ปรับเป็น (db, requireAuth, requireOwner)
  router.use(require('./room')(db, requireAuth, requireOwner));
  router.use(require('./roomImages')(db, requireAuth, requireOwner));
  router.use(require('./income')(db));       // ถ้าต้องการ auth ให้ปรับเป็น (db, requireAuth, requireOwner)
  router.use(require('./uploadQR')(db));
  router.use(require('./utilityRate')(db));
  router.use(require('./tenant')(db));
  router.use(requireAuth, requireOwner, require('./billing')(db));
  router.use(require('./repairs')(db, requireAuth, requireOwner));
  router.use(require('./owner-electric')(db, requireAuth, tuya));

  return router;
};
