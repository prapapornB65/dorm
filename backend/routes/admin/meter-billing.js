// backend/routes/admin/meter-billing.js
const express = require('express');
const router = express.Router();
const { Pool } = require('pg');
const { runMeterBilling } = require('../../services/meterBilling');

const db = new Pool({ connectionString: process.env.DATABASE_URL });

// TODO: แทนที่ด้วย middleware auth จริงของคุณ
function requireAdminOrOwner(req, res, next) {
  // ตัวอย่าง: req.user.role === 'admin' || req.user.role === 'owner'
  next();
}

/**
 * POST /admin/meters/run-billing
 * body: { meterId?, buildingId?, ownerId?, dryRun?: boolean, parallel?: number }
 */
router.post('/run-billing', requireAdminOrOwner, async (req, res) => {
  try {
    const { meterId, buildingId, ownerId, dryRun = false, parallel } = req.body || {};
    const summary = await runMeterBilling(db, { scope: { meterId, buildingId, ownerId }, dryRun, parallel });
    res.json({ ok: true, ...summary });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message || String(e) });
  }
});

/**
 * GET /internal/cron/meter-billing?token=CRON_SECRET&dryRun=0
 * ใช้ให้ task scheduler เรียกแบบไม่ต้อง login
 */
router.get('/cron', async (req, res) => {
  if (req.query.token !== process.env.CRON_SECRET) {
    return res.status(401).json({ ok: false, error: 'unauthorized' });
  }
  const dryRun = req.query.dryRun === '1';
  try {
    // เร็ว/นิ่ง: ตอบกลับก่อน แล้วทำงานต่อเบื้องหลัง
    res.json({ ok: true, accepted: true });
    setImmediate(async () => {
      await runMeterBilling(db, { scope: {}, dryRun });
    });
  } catch (e) {
    // หาก setImmediate เกิด exception จะไม่มาที่นี่ แต่แสดงไว้เผื่อโหมด await
    console.error('cron route error:', e);
  }
});

module.exports = router;
