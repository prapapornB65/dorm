// routes/index.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // ตัวอย่าง route กลุ่มเดิมของคุณ
  router.use('/owner', require('./owner')(db));
  router.use('/owner', require('./ownerApprovals')(db));       // -> /api/owner/...

  router.use('/', require('./ownerAccount')(db));  // -> /api/...
  router.use('/', require('./building')(db));
  router.use('/', require('./room')(db));
  router.use('/', require('./income')(db));
  router.use('/', require('./uploadQR')(db));
  router.use('/', require('./utilityRate')(db));
  router.use('/', require('./tenant')(db));
  router.use('/', require('./tuya')(db));
  router.use('/', require('./tuyaControl')(db));
  router.use('/', require('./billing')(db));

  return router;
};
