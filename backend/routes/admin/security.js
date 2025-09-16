const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /api/security/activities
  router.get('/security/activities', async (_req, res) => {
    try {
      const rows = await db.any(`
        SELECT "Date" AS date, "Account" AS account, "Activity" AS activity
        FROM public."Activities"
        ORDER BY "Date" DESC
        LIMIT 10;
      `);

      const formatted = rows.map(item => ({
        date: new Date(item.date).toLocaleDateString('th-TH', {
          year: 'numeric', month: 'short', day: 'numeric'
        }),
        account: item.account,
        activity: item.activity,
      }));

      res.json(formatted);
    } catch (error) {
      console.error('❌ Error fetching latest activities:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลกิจกรรมล่าสุด' });
    }
  });

  // GET /api/security/login-history
  router.get('/security/login-history', async (_req, res) => {
    try {
      const rows = await db.any(`
        SELECT "Date" AS date, "Account" AS account, "IPAddress" AS ip, "Status" AS status
        FROM public."LoginHistory"
        ORDER BY "Date" DESC
        LIMIT 10;
      `);

      const formatted = rows.map(item => ({
        date: new Date(item.date).toLocaleDateString('th-TH', {
          year: 'numeric', month: 'short', day: 'numeric'
        }),
        account: item.account,
        ip: item.ip,
        status: item.status,
      }));

      res.json(formatted);
    } catch (error) {
      console.error('❌ Error fetching login history:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลประวัติการเข้าสู่ระบบ' });
    }
  });

  return router;
};
