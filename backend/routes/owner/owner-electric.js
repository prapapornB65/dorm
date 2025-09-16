// routes/owner-electric.js
const express = require('express');

module.exports = function ownerElectricRoutes(db, tuya) {
  const router = express.Router();

  // ---- DB adapter: รองรับ pg-promise หรือ pg(Pool) ----
  const isPgPromise = typeof db.any === 'function';
  const qAny = (text, params=[]) =>
    isPgPromise ? db.any(text, params) : db.query(text, params).then(r => r.rows);
  const qOneOrNone = (text, params=[]) =>
    isPgPromise
      ? db.oneOrNone(text, params)
      : db.query(text, params).then(r => r.rows[0] || null);
  const qNone = (text, params=[]) =>
    isPgPromise ? db.none(text, params) : db.query(text, params).then(() => null);

  // ---------------- helpers ----------------
  async function getDpMap(deviceId) {
    const row = await qOneOrNone(
      `SELECT "RelayCode","RelayStatusCode","EnergyCode","PowerCode","VoltageCode","CurrentCode"
       FROM public."TuyaDevice" WHERE "DeviceID"=$1`,
      [deviceId]
    );
    const d = row || {};
    return {
      relay: d.RelayCode || 'switch_1',
      relayStatus: d.RelayStatusCode || 'relay_status',
      energy: d.EnergyCode || 'add_ele',
      power: d.PowerCode || 'cur_power',
      voltage: d.VoltageCode || 'cur_voltage',
      current: d.CurrentCode || 'cur_current',
    };
  }

  function pick(dpArray, code) {
    const hit = (dpArray || []).find(x => x.code === code);
    return hit?.value;
  }

  async function currentTenantWallet(roomNumber) {
    const t = await qOneOrNone(
      `SELECT "TenantID" FROM public."Tenant"
       WHERE "RoomNumber"=$1 AND ("End" IS NULL OR "End">now())
       ORDER BY "Start" DESC NULLS LAST
       LIMIT 1`,
      [roomNumber]
    );
    if (!t) return { tenantId: null, balance: 0 };

    const w = await qOneOrNone(
      `SELECT "Balance" FROM public."Wallet" WHERE "TenantID"=$1`,
      [t.TenantID]
    );
    return { tenantId: t.TenantID, balance: Number(w?.Balance || 0) };
  }

  // ============== ROUTES ==============

  // health check (ทดสอบว่า route ถูก mount แล้ว)
  router.get('/owner/electric/health', (req, res) => {
    res.json({ ok: true, route: 'owner-electric' });
  });

  /**
   * GET /owner/rooms/electric?q=
   */
  router.get('/owner/rooms/electric', async (req, res) => {
    try {
      const q = (req.query.q || '').trim();
      const where = q ? `WHERE r."RoomNumber" ILIKE $1 OR td."DeviceID" ILIKE $1` : '';
      const params = q ? [`%${q}%`] : [];

      const rows = await qAny(
        `SELECT r."RoomNumber", td."DeviceID",
                v."UpdatedAt", v."EnergyKwh", v."PowerW"
         FROM public."Room" r
         LEFT JOIN public."TuyaDevice" td ON td."RoomNumber"=r."RoomNumber" AND td."Active"=TRUE
         LEFT JOIN public."v_OwnerRoomElectric" v ON v."RoomNumber"=r."RoomNumber"
         ${where}
         ORDER BY r."RoomNumber" ASC`,
        params
      );

      const out = [];
      for (const r of rows) {
        const { balance } = await currentTenantWallet(r.RoomNumber);
        out.push({
          room_id: r.RoomNumber,
          device_id: r.DeviceID || null,
          relay_on: null, // จะอัปเดตตอน pull
          energy_kwh: Number(r.EnergyKwh || 0),
          power_w: Number(r.PowerW || 0),
          wallet_balance: Number(balance),
          updated_at: r.UpdatedAt || null,
        });
      }
      res.json({ data: out });
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: e.message });
    }
  });

  /**
   * POST /owner/rooms/:roomId/pull-electric
   */
  router.post('/owner/rooms/:roomId/pull-electric', async (req, res) => {
    const roomNumber = req.params.roomId;
    try {
      const row = await qOneOrNone(
        `SELECT "DeviceID" FROM public."TuyaDevice"
         WHERE "RoomNumber"=$1 AND "Active"=TRUE LIMIT 1`,
        [roomNumber]
      );
      const deviceId = row?.DeviceID;
      if (!deviceId) return res.status(404).json({ error: 'Device not found for room' });

      const dp = await getDpMap(deviceId);

      const api = await tuya.request({
        method: 'GET',
        path: `/v1.0/iot-03/devices/${deviceId}/status`,
      });
      if (!api.success) return res.status(502).json(api);

      const arr = api.result || [];
      const energy = Number(pick(arr, dp.energy)) || null;
      const power  = Number(pick(arr, dp.power))  || null;
      const volt   = Number(pick(arr, dp.voltage))|| null;
      const curr   = Number(pick(arr, dp.current))|| null;
      const relayS = pick(arr, dp.relayStatus);

      await qNone(
        `INSERT INTO public."ElectricReading"
         ("RoomNumber","DeviceID","EnergyKwh","PowerW","VoltageV","CurrentA")
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [roomNumber, deviceId, energy, power, volt, curr]
      );

      res.json({
        data: {
          room_id: roomNumber,
          device_id: deviceId,
          relay_on: (relayS === 1 || relayS === '1' || relayS === true),
          energy_kwh: energy || 0,
          power_w: power || 0,
          updated_at: new Date().toISOString(),
        }
      });
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: e.message });
    }
  });

  /**
   * POST /owner/rooms/:roomId/relay   { on: true|false }
   */
  router.post('/owner/rooms/:roomId/relay', async (req, res) => {
    const roomNumber = req.params.roomId;
    const on = !!req.body.on;
    try {
      const row = await qOneOrNone(
        `SELECT "DeviceID","RelayCode"
         FROM public."TuyaDevice"
         WHERE "RoomNumber"=$1 AND "Active"=TRUE LIMIT 1`,
        [roomNumber]
      );
      if (!row) return res.status(404).json({ error: 'Device not found for room' });

      const code = row.RelayCode || 'switch_1';
      const resp = await tuya.request({
        method: 'POST',
        path: `/v1.0/iot-03/devices/${row.DeviceID}/commands`,
        body: { commands: [{ code, value: on }] }
      });
      if (!resp.success) return res.status(502).json(resp);

      res.json({ ok: true });
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: e.message });
    }
  });

  return router;
};
