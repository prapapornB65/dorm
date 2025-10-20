// routes/owner/equipment.js  (PostgreSQL + pg-promise)
const express = require('express');

module.exports = (db, requireAuth) => {  // 👈 เพิ่มตรงนี้!
  const router = express.Router();
  
  router.get('/equipment',  async (_req, res) => {
    try {
      const rows = await db.any(
        `SELECT "EquipmentID","EquipmentName"
           FROM "Equipment"
       ORDER BY "EquipmentName" ASC`
      );
      res.json(rows); // ส่งเป็น array ตรง ๆ
    } catch (e) {
      console.error('[equipment:list]', e);
      res.status(500).json({ error: 'Failed to fetch equipment catalog' });
    }
  });

  // POST /api/equipment  { EquipmentName }
  router.post('/equipment',  async (req, res) => {
    try {
      const name = (req.body?.EquipmentName || '').trim();
      if (!name) return res.status(400).json({ error: 'EquipmentName is required' });

      const dup = await db.oneOrNone(
        `SELECT 1 FROM "Equipment" WHERE LOWER("EquipmentName")=LOWER($1)`,
        [name]
      );
      if (dup) return res.status(409).json({ error: 'Equipment already exists' });

      await db.none(`INSERT INTO "Equipment"("EquipmentName") VALUES ($1)`, [name]);
      res.status(201).json({ ok: true });
    } catch (e) {
      console.error('[equipment:create]', e);
      res.status(500).json({ error: 'Failed to create equipment' });
    }
  });

  // ===== 2) ความสัมพันธ์เจ้าของ ↔ อุปกรณ์ =====
  // GET /api/owner/:ownerId/equipments  -> [EquipmentID,...]
  router.get('/:ownerId/equipments',  async (req, res) => {
    try {
      const ownerId = parseInt(req.params.ownerId, 10);
      if (!ownerId) return res.status(400).json({ error: 'bad ownerId' });

      const rows = await db.any(
        `SELECT "EquipmentID"
           FROM "OwnerEquipment"
          WHERE "OwnerID"=$1
       ORDER BY "EquipmentID" ASC`,
        [ownerId]
      );
      res.json(rows.map(r => r.EquipmentID));
    } catch (e) {
      console.error('[owner/equipments:get]', e);
      res.status(500).json({ error: 'Failed to fetch owner equipments' });
    }
  });

  // POST /api/owner/:ownerId/equipments  {equipmentIds:[...]}
  router.post('/:ownerId/equipments',  async (req, res) => {
    const ownerId = parseInt(req.params.ownerId, 10);
    if (!ownerId) return res.status(400).json({ error: 'bad ownerId' });

    const idsRaw = Array.isArray(req.body?.equipmentIds) ? req.body.equipmentIds : [];
    const ids = idsRaw.map(v => {
      if (v && typeof v === 'object' && v.EquipmentID != null) return parseInt(v.EquipmentID, 10);
      return parseInt(v, 10);
    }).filter(n => Number.isInteger(n) && n > 0);

    try {
      await db.tx(async t => {
        await t.none(`DELETE FROM "OwnerEquipment" WHERE "OwnerID"=$1`, [ownerId]);

        if (ids.length) {
          // ยืนยันว่ามีอยู่จริงใน Equipment
          const valid = await t.any(
            `SELECT "EquipmentID" FROM "Equipment" WHERE "EquipmentID" IN ($1:csv)`,
            [ids]
          );
          const okIds = new Set(valid.map(r => r.EquipmentID));

          const inserts = ids
            .filter(id => okIds.has(id))
            .map(id => t.none(
              `INSERT INTO "OwnerEquipment"("OwnerID","EquipmentID") VALUES ($1,$2)`,
              [ownerId, id]
            ));

          await t.batch(inserts);
          const invalid = ids.filter(id => !okIds.has(id));
          return { count: okIds.size, invalid };
        }
        return { count: 0, invalid: [] };
      }).then(result => res.json({ ok: true, ...result }));
    } catch (e) {
      console.error('[owner/equipments:post]', e);
      res.status(500).json({ error: 'Failed to save owner equipments' });
    }
  });

  return router;
};