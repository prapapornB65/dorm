const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // -------- ต้องการ db --------
  router.use(require('./account')(db));
  router.use(require('./room')(db));
  router.use(require('./walletPayment')(db));
  router.use(require('./usageHistory')(db));
  router.use(require('./uploads')(db));

  router.use('/unit-balance', require('./unitBalance')(db));
  router.use('/unit-purchase', require('./unitPurchase')(db));
  router.use('/wallet', require('./wallet')(db));

  router.use(require('./meters')(db));

  router.use(require('./slipUploadRoute')); 
  router.use(require('./regis'));           
  return router;
};
