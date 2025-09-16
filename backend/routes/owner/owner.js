const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  router.get('/:id', async (req, res) => {
    const ownerId = req.params.id;
    try {
      const result = await db.oneOrNone(
        'SELECT "FirstName","LastName","ApiKey","ProjectID" FROM "Owner" WHERE "OwnerID"=$1',
        [ownerId]
      );
      if (!result) return res.status(404).json({ error: true, message: 'ไม่พบเจ้าของหอพัก' });
      const fullName = `${result.FirstName} ${result.LastName}`;
      res.json({ error: false, ownerName: fullName, apiKey: result.ApiKey, projectId: result.ProjectID });
    } catch (err) {
      console.error('❌ Error fetching owner:', err);
      res.status(500).json({ error: true, message: 'ดึงข้อมูลเจ้าของหอพักล้มเหลว' });
    }
  });

  return router;
};
