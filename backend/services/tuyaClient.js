// services/tuyaClient.js
const ACCESS_ID     = process.env.TUYA_ACCESS_ID || '';
const ACCESS_SECRET = process.env.TUYA_ACCESS_SECRET || '';
const BASE          = process.env.TUYA_BASE || 'https://openapi.tuyaus.com';
const USE_EMU       = process.env.TUYA_EMULATOR === '1';

let TuyaOpenAPICls = null;
let openapi = null;
let connecting = null;

function toMap(arr) {
  const m = {};
  (arr || []).forEach((x) => { if (x && x.code != null) m[x.code] = x.value; });
  return m;
}

async function ensureClient() {
  if (USE_EMU) return null;

  if (!TuyaOpenAPICls) {
    try {
      ({ TuyaOpenAPI: TuyaOpenAPICls } = require('@tuya/tuya-connector-nodejs'));
    } catch {
      try {
        ({ TuyaOpenAPI: TuyaOpenAPICls } = require('tuya-connector-nodejs')); // เผื่อใช้แพ็กเกจเก่า
      } catch {}
    }
  }
  if (!TuyaOpenAPICls) {
    console.warn('[tuyaClient] SDK not found, fallback to emulator.');
    return null;
  }
  if (!openapi) {
    openapi = new TuyaOpenAPICls(BASE, ACCESS_ID, ACCESS_SECRET);
    connecting = connecting || openapi.connect();
    await connecting;
  }
  return openapi;
}

async function getDeviceStatus(deviceId) {
  const client = await ensureClient();
  if (!client) {
    // โหมด emulator: สร้างค่าจำลองให้โตขึ้นเรื่อย ๆ
    const now = Date.now();
    const power = 200 + (now % 150);
    return {
      add_ele: ((now / 1000) % 100000) / 50, // kWh สะสม
      cur_power: power,                       // W
      cur_voltage: 220,                       // V
      cur_current: +(power / 220).toFixed(2), // A
    };
  }
  const resp = await client.get(`/v1.0/devices/${deviceId}/status`);
  return toMap(resp?.result);
}

module.exports = { getDeviceStatus };
