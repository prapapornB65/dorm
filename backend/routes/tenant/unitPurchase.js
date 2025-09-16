// ของเดิม: POST /  ตรวจ wallet – หักเงิน – INSERT UtilityPurchase – อัปเดต/แทรก UnitBalance (transaction)
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // POST /api/unit-purchase/
  router.post('/', async (req, res) => {
    let { tenantId, waterUnit, electricUnit, waterUnitPrice, electricUnitPrice } = req.body;

    tenantId = parseInt(tenantId);
    waterUnit = parseFloat(waterUnit);
    electricUnit = parseFloat(electricUnit);
    waterUnitPrice = parseFloat(waterUnitPrice);
    electricUnitPrice = parseFloat(electricUnitPrice);

    if (
      !tenantId ||
      isNaN(waterUnit) || waterUnit < 0 ||
      isNaN(electricUnit) || electricUnit < 0 ||
      isNaN(waterUnitPrice) || waterUnitPrice < 0 ||
      isNaN(electricUnitPrice) || electricUnitPrice < 0
    ) {
      return res.status(400).json({ error: 'ข้อมูลไม่ถูกต้อง' });
    }

    const totalAmount = (waterUnit * waterUnitPrice) + (electricUnit * electricUnitPrice);

    try {
      await db.tx(async t => {
        const wallet = await t.one(
          `SELECT "Balance" FROM "Wallet" WHERE "TenantID"=$1 FOR UPDATE`,
          [tenantId]
        );
        if (Number(wallet.Balance) < totalAmount) throw new Error('ยอดเงินไม่เพียงพอ');

        await t.none(
          `UPDATE "Wallet" SET "Balance"="Balance" - $1 WHERE "TenantID"=$2`,
          [totalAmount, tenantId]
        );

        await t.none(`
          INSERT INTO "UtilityPurchase" (
            "TenantID","PurchaseDate","WaterUnit","ElectricUnit",
            "WaterUnitPrice","ElectricUnitPrice","TotalAmount"
          ) VALUES ($1, CURRENT_TIMESTAMP, $2, $3, $4, $5, $6)
        `, [tenantId, waterUnit, electricUnit, waterUnitPrice, electricUnitPrice, totalAmount]);

        const updateCount = await t.result(`
          UPDATE "UnitBalance"
          SET "WaterUnit"="WaterUnit"+$1,
              "ElectricUnit"="ElectricUnit"+$2,
              "LastUpdated"=CURRENT_TIMESTAMP
          WHERE "TenantID"=$3
        `, [waterUnit, electricUnit, tenantId]);

        if (updateCount.rowCount === 0) {
          await t.none(`
            INSERT INTO "UnitBalance" ("TenantID","WaterUnit","ElectricUnit","LastUpdated")
            VALUES ($1,$2,$3,CURRENT_TIMESTAMP)
          `, [tenantId, waterUnit, electricUnit]);
        }
      });

      res.json({ message: 'ซื้อหน่วยสำเร็จ', totalAmount });
    } catch (error) {
      console.error('Error during purchase:', error);
      const errorMsg = error.message === 'ยอดเงินไม่เพียงพอ' ? error.message : 'เกิดข้อผิดพลาดในการซื้อหน่วย';
      res.status(400).json({ error: errorMsg });
    }
  });

  return router;
};
