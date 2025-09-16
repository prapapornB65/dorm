
require('dotenv').config();
const { TuyaOpenAPI } = require('@tuya/tuya-connector-nodejs');

const {
  TUYA_BASE_URL,
  TUYA_ACCESS_ID,
  TUYA_ACCESS_KEY,
  TUYA_DEVICE_ID
} = process.env;

async function main() {
  const api = new TuyaOpenAPI(TUYA_BASE_URL, TUYA_ACCESS_ID, TUYA_ACCESS_KEY);
  await api.connect(); // สร้าง session/token

  // 1) ฟังก์ชัน (DP ที่สั่งได้) — ใช้ดูว่ามี code อะไรควบคุมได้บ้าง
  const funcs = await api.get(`/v1.0/devices/${TUYA_DEVICE_ID}/functions`);
  console.log('\\n=== DEVICE FUNCTIONS (DP controllable) ===');
  console.log(JSON.stringify(funcs.result ?? funcs, null, 2));

  // 2) สถานะปัจจุบันของทุก DP
  const status = await api.get(`/v1.0/devices/${TUYA_DEVICE_ID}/status`);
  console.log('\\n=== DEVICE STATUS (DP values) ===');
  console.log(JSON.stringify(status.result ?? status, null, 2));

  // 3) (ตัวอย่าง) สั่งอุปกรณ์ — เปลี่ยน code/value ให้ตรงกับ DP ของคุณ
  // await api.post(`/v1.0/devices/${TUYA_DEVICE_ID}/commands`, {
  //   commands: [{ code: 'switch_1', value: true }]
  // });
  // console.log('\\nCommand sent: switch_1 = true');
}

main().catch(err => {
  // แสดง error แบบอ่านง่าย
  const e = err?.response ? { status: err.response.status, data: err.response.data } : err;
  console.error('\\nERROR:', e);
});

