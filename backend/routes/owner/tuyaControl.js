// routes/tuyaControl.js
const express = require('express');
const { TuyaContext } = require('@tuya/tuya-connector-nodejs');

const ctx = new TuyaContext({
  baseUrl: process.env.TUYA_BASE_URL,   // ให้ตรง region เดียวกับโปรเจ็กต์ (เช่น SG มักใช้ https://openapi.tuyaus.com)
  accessKey: process.env.TUYA_AK,
  secretKey: process.env.TUYA_SK,
});

module.exports = (db) => {
  const router = express.Router();

  // อ่านสถานะ DP ปัจจุบัน
  router.get('/tuya/status/:deviceId', async (req, res) => {
    try {
      const { deviceId } = req.params;
      const r = await ctx.request({
        method: 'GET',
        path: `/v1.0/iot-03/devices/${deviceId}/status`,
      });
      res.json(r);
    } catch (e) { res.status(500).json({ error: String(e) }); }
  });

  // สลับสวิตช์ (on=true -> ต่อไฟ, on=false -> ตัด)
  router.post('/tuya/switch', async (req, res) => {
    try {
      const { deviceId, on, code = 'switch_1' } = req.body;
      const r = await ctx.request({
        method: 'POST',
        path: `/v1.0/iot-03/devices/${deviceId}/commands`,
        body: { commands: [{ code, value: !!on }] },
      });
      res.json(r);
    } catch (e) { res.status(500).json({ error: String(e) }); }
  });

  // (ทางเลือก) ตัด/ต่อ โดยอ้างอิง meter_id แล้วให้ backend หา deviceId เอง
  router.post('/meter/:meterId/cut', async (req, res) => {
    const { meterId } = req.params;
    const row = await db.oneOrNone(
      `SELECT td."DeviceID" as device_id, COALESCE(td.dp_map->>'cut_switch','switch_1') as code
       FROM "Meter" m JOIN "TuyaDevice" td ON td."id" = m."TuyaDeviceID"
       WHERE m."id" = $1`, [meterId]);
    if (!row) return res.status(404).json({ error: 'meter not mapped' });
    const r = await ctx.request({
      method:'POST',
      path:`/v1.0/iot-03/devices/${row.device_id}/commands`,
      body:{ commands:[{ code: row.code, value:false }] }  // false = CUT
    });
    await db.none(`UPDATE "TuyaDevice" SET is_cut = TRUE, last_cut_at = now() WHERE "DeviceID"=$1`, [row.device_id]);
    res.json(r);
  });

  router.post('/meter/:meterId/resume', async (req, res) => {
    const { meterId } = req.params;
    const row = await db.oneOrNone(
      `SELECT td."DeviceID" as device_id, COALESCE(td.dp_map->>'cut_switch','switch_1') as code
       FROM "Meter" m JOIN "TuyaDevice" td ON td."id" = m."TuyaDeviceID"
       WHERE m."id" = $1`, [meterId]);
    if (!row) return res.status(404).json({ error: 'meter not mapped' });
    const r = await ctx.request({
      method:'POST',
      path:`/v1.0/iot-03/devices/${row.device_id}/commands`,
      body:{ commands:[{ code: row.code, value:true }] }   // true = RESUME
    });
    await db.none(`UPDATE "TuyaDevice" SET is_cut = FALSE WHERE "DeviceID"=$1`, [row.device_id]);
    res.json(r);
  });

  return router;
};
