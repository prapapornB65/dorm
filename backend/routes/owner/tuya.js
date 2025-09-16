const express = require('express');
const { getDeviceStatus } = require('../../services/tuyaClient');

function num(x) { const n = Number(x); return Number.isFinite(n) ? n : 0; }

module.exports = (db) => {
  const router = express.Router();

  // POST /api/building/:buildingId/tuya/pull-electric
  // ดึงสถานะจากอุปกรณ์ทุกตัวในตึกนี้ แล้ว INSERT ลง ElectricReading
  router.post('/building/:buildingId/tuya/pull-electric', async (req, res) => {
    const buildingId = Number(req.params.buildingId);
    if (!buildingId) return res.status(400).json({ error: 'invalid buildingId' });

    try {
      const devices = await db.any(`
        SELECT td."DeviceID", td."RoomNumber",
               td."EnergyCode", td."PowerCode", td."VoltageCode", td."CurrentCode"
        FROM "TuyaDevice" td
        JOIN "Room" r ON r."RoomNumber" = td."RoomNumber"
        WHERE r."BuildingID" = $1 AND td."Active" = TRUE
      `, [buildingId]);

      const rows = [];
      for (const d of devices) {
        const st = await getDeviceStatus(d.DeviceID);
        // เผื่อ device ของคุณใช้ code มาตรฐานของ Tuya
        const kwh     = num(st[d.EnergyCode]  ?? st.add_ele     ?? 0);
        const powerW  = num(st[d.PowerCode]   ?? st.cur_power   ?? 0);
        const voltage = num(st[d.VoltageCode] ?? st.cur_voltage ?? 0);
        const current = num(st[d.CurrentCode] ?? st.cur_current ?? 0);

        await db.none(`
          INSERT INTO "ElectricReading"
            ("RoomNumber","DeviceID","At","EnergyKwh","PowerW","VoltageV","CurrentA")
          VALUES ($1,$2,NOW(),$3,$4,$5,$6)
        `, [d.RoomNumber, d.DeviceID, kwh, powerW, voltage, current]);

        rows.push({ room: d.RoomNumber, deviceId: d.DeviceID, kwh, powerW, voltage, current });
      }

      res.json({ ok: true, inserted: rows.length, rows });
    } catch (e) {
      console.error('pull-electric error', e);
      res.status(500).json({ error: String(e?.message || e) });
    }
  });

  return router;
};
