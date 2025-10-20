// routes/tuyaControl.js
const express = require('express');
const { buildTuyaContextWithDebug } = require('../utils/tuyaSafe');

// รองรับการเรียกแบบหลายอาร์กิวเมนต์: (tuyaCtx, requireAuth) หรือ (requireAuth) หรือ (db, tuyaCtx, requireAuth, ...)
function pickTuyaCtx(args){
  for (const a of args) {
    if (a && typeof a.request === 'function') return a; // TuyaContext
  }
  return null;
}
function pickMiddleware(args){
  for (const a of args) if (typeof a === 'function') return a;
  return (_req,_res,next)=>next();
}

module.exports = (...args) => {
  const router = express.Router();
  const requireAuth = pickMiddleware(args);
  const tuya = pickTuyaCtx(args) || buildTuyaContextWithDebug('server');

  router.get('/tuya/status/:deviceId', requireAuth, async (req,res)=>{
    try{
      const r = await tuya.request({
        method:'GET',
        path:`/v1.0/iot-03/devices/${req.params.deviceId}/status`
      });
      res.status(r?.success?200:502).json(r);
    }catch(e){
      res.status(502).json({ ok:false, error:'TUYA_REQUEST_FAILED', detail:e?.response?.data||e?.message||String(e) });
    }
  });

  return router;
};
