// ของเดิม: PUT /deduct  (หักเงินจาก wallet)
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // PUT /api/wallet/deduct
  router.put('/deduct', async (req, res) => {
    const tenantId = Number(req.body.tenantId);
    const amount = Number(req.body.amount);

    if (!Number.isInteger(tenantId) || !Number.isFinite(amount) || amount <= 0) {
      return res.status(400).json({ error: 'ข้อมูล tenantId หรือ amount ไม่ถูกต้อง' });
    }

    try {
      const result = await db.result(`
        UPDATE "Wallet"
        SET "Balance"="Balance" - $2
        WHERE "TenantID"=$1 AND "Balance" >= $2
      `, [tenantId, amount]);

      if (result.rowCount === 0) return res.status(400).json({ error: 'ยอดเงินไม่เพียงพอ หรือไม่พบผู้ใช้' });
      res.json({ message: 'หักเงินสำเร็จ' });
    } catch (err) {
      console.error('❌ Error deducting wallet:', err);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการหักเงิน' });
    }
  });

  return router;
};
