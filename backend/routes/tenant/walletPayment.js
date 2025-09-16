// routes/tenant/walletPayment.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /api/wallet/:tenantId  (autocreate if missing)
  router.get('/wallet/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const rows = await db.any(`SELECT * FROM public."Wallet" WHERE "TenantID"=$1`, [tenantId]);
      if (rows.length === 0) {
        const created = await db.one(
          `INSERT INTO public."Wallet" ("TenantID","Balance") VALUES ($1,0) RETURNING *`,
          [tenantId]
        );
        return res.status(201).json(created);
      }
      res.json(rows[0]);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงหรือสร้าง Wallet' });
    }
  });

  // POST /api/pay-rent
  router.post('/pay-rent', async (req, res) => {
    const tenantId = Number(req.body.tenantId);
    const amount = Number(req.body.amount);
    if (!Number.isInteger(tenantId) || !Number.isFinite(amount) || amount <= 0) {
      return res.status(400).json({ error: 'tenantId และ amount ต้องเป็นตัวเลขและ amount > 0' });
    }

    try {
      await db.tx(async t => {
        const wallet = await t.oneOrNone(
          `SELECT "Balance" FROM public."Wallet" WHERE "TenantID"=$1 FOR UPDATE`,
          [tenantId]
        );
        if (!wallet || Number(wallet.Balance) < amount) throw new Error('ยอดเงินใน Wallet ไม่เพียงพอ');

        await t.none(`UPDATE public."Wallet" SET "Balance"="Balance"-$1 WHERE "TenantID"=$2`, [amount, tenantId]);

        const payment = await t.one(`
          INSERT INTO public."Payment" ("TenantID","TotalAmount","PaymentMethod","Status","PaymentDate")
          VALUES ($1,$2,$3,$4,NOW()) RETURNING "PaymentID"
        `, [tenantId, amount, 'Wallet', 'Success']);

        const now = new Date();
        const month = now.getMonth() + 1;
        const year = now.getFullYear();

        await t.none(`
          INSERT INTO public."PaymentDetail" ("ItemType","Month","Year","Amount","PaymentID")
          VALUES ('Room',$1,$2,$3,$4)
        `, [month, year, amount, payment.PaymentID]);
      });

      res.json({ message: 'ชำระค่าห้องเรียบร้อยแล้ว' });
    } catch (e) {
      console.error('❌ /api/pay-rent:', e.message);
      res.status(400).json({ error: e.message || 'เกิดข้อผิดพลาดในการชำระเงิน' });
    }
  });

  // GET /api/utilitypurchases/:tenantId
  router.get('/utilitypurchases/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const rows = await db.any(`
        SELECT * FROM public."UtilityPurchase" 
        WHERE "TenantID"=$1 ORDER BY "PurchaseDate" DESC
      `, [tenantId]);
      res.json(rows);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูล UtilityPurchase' });
    }
  });

  // GET /api/payments/:tenantId
  router.get('/payments/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const payments = await db.any(`
        SELECT * FROM public."Payment" WHERE "TenantID"=$1 ORDER BY "PaymentDate" DESC
      `, [tenantId]);

      for (const p of payments) {
        p.details = await db.any(`SELECT * FROM public."PaymentDetail" WHERE "PaymentID"=$1`, [p.PaymentID]);
      }
      res.json(payments);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูล Payment' });
    }
  });

  return router;
};
