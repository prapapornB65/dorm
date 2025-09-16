const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /api/admin-id-by-uid/:firebaseUID
  router.get('/admin-id-by-uid/:firebaseUID', async (req, res) => {
    const { firebaseUID } = req.params;
    try {
      const admin = await db.oneOrNone(
        'SELECT "AdminID" FROM "Admin" WHERE "FirebaseUID" = $1',
        [firebaseUID]
      );
      if (!admin) return res.status(404).json({ error: 'ไม่พบ Admin ที่ตรงกับ UID นี้' });
      res.json(admin);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return router;
};
