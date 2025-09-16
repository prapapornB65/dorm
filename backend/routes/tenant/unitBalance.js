// อ้างอิงของเดิม: มี GET /:tenantId, PUT /add, PUT /deduct  (รวมเวอร์ชันที่ auto-create) 
// แก้ให้เสถียรและคืน 400 เมื่อ tenantId ไม่ใช่ตัวเลข
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /api/unit-balance/:tenantId  (auto-create ถ้าไม่มี)
  router.get('/:tenantId', async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) return res.status(400).json({ error: 'tenantId ต้องเป็นตัวเลข' });

    try {
      const row = await db.oneOrNone(`
        SELECT "WaterUnit","ElectricUnit","LastUpdated"
        FROM "UnitBalance" WHERE "TenantID"=$1
      `, [tenantId]);

      if (!row) {
        const inserted = await db.one(`
          INSERT INTO "UnitBalance" ("TenantID","WaterUnit","ElectricUnit","LastUpdated")
          VALUES ($1,0,0,CURRENT_TIMESTAMP)
          RETURNING "WaterUnit","ElectricUnit","LastUpdated"
        `, [tenantId]);
        return res.status(201).json(inserted);
      }
      res.json(row);
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึง/สร้าง UnitBalance' });
    }
  });

  // PUT /api/unit-balance/add
  router.put('/add', async (req, res) => {
    const { tenantId, waterUnit = 0, electricUnit = 0 } = req.body;
    if (!Number.isInteger(Number(tenantId))) return res.status(400).json({ error: 'ต้องระบุ tenantId เป็นตัวเลข' });
    if (waterUnit < 0 || electricUnit < 0) return res.status(400).json({ error: 'จำนวนหน่วยต้องไม่ติดลบ' });

    try {
      const result = await db.result(`
        UPDATE "UnitBalance"
        SET "WaterUnit"="WaterUnit"+$2,
            "ElectricUnit"="ElectricUnit"+$3,
            "LastUpdated"=CURRENT_TIMESTAMP
        WHERE "TenantID"=$1
      `, [tenantId, waterUnit, electricUnit]);

      if (result.rowCount === 0) return res.status(404).json({ error: 'ไม่พบ TenantID นี้' });
      res.json({ message: 'เติมหน่วยสำเร็จ' });
    } catch (err) {
      console.error('❌ Error:', err);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการเติมหน่วย' });
    }
  });

  // PUT /api/unit-balance/deduct
  router.put('/deduct', async (req, res) => {
    const { tenantId, waterUnit = 0, electricUnit = 0 } = req.body;
    if (!Number.isInteger(Number(tenantId))) return res.status(400).json({ error: 'ต้องระบุ tenantId เป็นตัวเลข' });
    if (waterUnit < 0 || electricUnit < 0) return res.status(400).json({ error: 'จำนวนหน่วยต้องไม่ติดลบ' });

    try {
      const result = await db.result(`
        UPDATE "UnitBalance"
        SET "WaterUnit"="WaterUnit" - $2,
            "ElectricUnit"="ElectricUnit" - $3,
            "LastUpdated"=CURRENT_TIMESTAMP
        WHERE "TenantID"=$1
          AND "WaterUnit" >= $2
          AND "ElectricUnit" >= $3
      `, [tenantId, waterUnit, electricUnit]);

      if (result.rowCount === 0) return res.status(400).json({ error: 'หน่วยไม่เพียงพอ หรือไม่พบผู้เช่า' });
      res.json({ message: 'หักหน่วยสำเร็จ' });
    } catch (err) {
      console.error('❌ Error:', err);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการหักหน่วย' });
    }
  });

  return router;
};
