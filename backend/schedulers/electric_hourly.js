// schedulers/electric_hourly.js
const cron = require('node-cron');
require('dotenv').config();

module.exports = function createElectricCron({ app, db /*, baseUrl*/ }) {
  const isPgPromise = typeof db.any === 'function';
  const qAny  = (t,p=[]) => isPgPromise ? db.any(t,p) : db.query(t,p).then(r => r.rows);
  const qOne  = (t,p=[]) => isPgPromise ? db.one(t,p) : db.query(t,p).then(r => r.rows[0]);
  // const qNone = (t,p=[]) => isPgPromise ? db.none(t,p) : db.query(t,p).then(()=>{}); // ไม่ได้ใช้

  const SPEC     = process.env.ELECTRIC_CRON_SPEC || '*/1 * * * *';
  const ENABLED  = String(process.env.ELECTRIC_CRON_ENABLED || '').toLowerCase() === 'true';
  const TZ       = process.env.TZ || 'Asia/Bangkok';
  const PARALLEL = Number(process.env.ELECTRIC_PARALLEL || 3);
  const DRY_RUN  = String(process.env.ELECTRIC_DRY_RUN || 'false') === 'true';

  const { runMeterBilling } = require('../services/meterBilling');

  async function withLock(lockId, fn) {
    const row = await qOne('SELECT pg_try_advisory_lock($1) AS ok', [lockId]);
    if (!row || row.ok !== true) return { skipped: true };
    try {
      return await fn();
    } finally {
      await qOne('SELECT pg_advisory_unlock($1) AS ok', [lockId]);
    }
  }

  async function listBuildingsWithActiveMeters() {
    const rows = await qAny(`
      SELECT DISTINCT td.building_id AS "buildingId"
      FROM "TuyaDevice" td
      WHERE COALESCE(td."Active", FALSE) IS TRUE
      ORDER BY td.building_id ASC
    `);
    return rows.map(r => Number(r.buildingId)).filter(n => Number.isInteger(n));
  }

  async function runOnce() {
    // ล็อกทั้งงานกันชนกันหลายโปรเซส
    const lockAll = 662001;

    const got = await withLock(lockAll, async () => {
      const started = Date.now();
      const buildings = await listBuildingsWithActiveMeters();
      const results = [];

      for (const b of buildings) {
        const lockB = 662100 + b; // ล็อกแยกต่อ-ตึก
        const r = await withLock(lockB, async () => {
          const begun = Date.now();
          try {
            const body = await runMeterBilling(db, {
              scope: { buildingId: b },
              parallel: PARALLEL,
              dryRun: DRY_RUN,
            });
            const tookMs = Date.now() - begun;
            console.log('[ELECTRIC_CRON] building:%d OK took=%dms summary=%s',
              b, tookMs, JSON.stringify(body));
            return { buildingId: b, status: 200, body, tookMs };
          } catch (e) {
            const tookMs = Date.now() - begun;
            console.warn('[ELECTRIC_CRON] building:%d failed after %dms: %s',
              b, tookMs, String(e?.message || e));
            return { buildingId: b, status: 500, body: { error: String(e?.message || e) }, tookMs };
          }
        });

        if (r && !r.skipped) results.push(r);
      }

      const tookMs = Date.now() - started;
      return { ok: true, tookMs, buildings: results };
    });

    if (got && got.skipped) {
      console.warn('[ELECTRIC_CRON] skip-lock (another cron running)');
      return { ok: false, reason: 'skip-lock' };
    }
    return got;
  }

  function start() {
    if (!ENABLED) {
      console.warn('[ELECTRIC_CRON] disabled');
      return { runOnce, stop: () => {} };
    }
    console.log('[ELECTRIC_CRON] schedule:', SPEC, 'TZ=', TZ);
    const task = cron.schedule(SPEC, async () => {
      console.time('[ELECTRIC_CRON] cycle');
      try {
        // กันชน peak ผู้ใช้เล็กน้อย
        await new Promise(r => setTimeout(r, Math.floor(Math.random() * 12000)));
        const r = await runOnce();
        const brief = {
          ok: r?.ok ?? false,
          tookMs: r?.tookMs ?? 0,
          buildings: (r?.buildings || []).map(x => ({
            b: x.buildingId, st: x.status, ms: x.tookMs
          })),
        };
        console.log('[ELECTRIC_CRON] done', JSON.stringify(brief));
      } catch (e) {
        console.error('[ELECTRIC_CRON] error', e);
      } finally {
        console.timeEnd('[ELECTRIC_CRON] cycle');
      }
    }, { timezone: TZ });

    return { runOnce, stop: () => task.stop() };
  }

  return { start, runOnce };
};

// ถ้าต้องการให้รันไฟล์นี้เดี่ยวๆ ก็ทำได้:
// if (require.main === module) module.exports({ db: require('../db').db }).start();
