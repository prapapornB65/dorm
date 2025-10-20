// services/tuyaClient.js
const { buildTuyaContextWithDebug } = require('../utils/tuyaSafe');

let ctx = null;
async function getCtx() {
  if (!ctx) ctx = buildTuyaContextWithDebug('client'); // ใช้ตัวเดียวกับส่วนอื่น
  return ctx;
}

async function getDeviceStatus(deviceId){
  const c = await getCtx();
  const r = await c.request({ method:'GET', path:`/v1.0/iot-03/devices/${deviceId}/status` });
  if (!r?.success) throw new Error(`tuya_failed_${r?.code||'NA'}`);
  const flat = {};
  for (const s of (r.result || [])) flat[s.code] = s.value;
  return flat;
}

async function sendDeviceCommand(deviceId, code, value){
  const c = await getCtx();
  const r = await c.request({
    method:'POST',
    path:`/v1.0/iot-03/devices/${deviceId}/commands`,
    body:{ commands:[{ code, value }] }
  });
  if (!r?.success) throw new Error(`tuya_failed_${r?.code||'NA'}`);
  return true;
}

module.exports = { getDeviceStatus, sendDeviceCommand };
