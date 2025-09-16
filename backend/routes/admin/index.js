const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  router.use(require('./account')(db));
  router.use(require('./dorm')(db));
  router.use(require('./notifications')(db));
  router.use(require('./security')(db));
  router.use(require('./meter-billing')(db));

  return router;
};
