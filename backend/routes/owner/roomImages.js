// routes/owner/roomImages.js
const express = require('express');
const path = require('path');
const fs = require('fs');

module.exports = (_db, requireAuth, requireOwner) => {
  const router = express.Router();

  // ป้องกันด้วย requireAuth + requireOwner เพื่อให้ idToken promotion ใน /api ทำงาน
  router.get('/room-images/:roomNumber', requireAuth, requireOwner, async (req, res) => {
    try {
      const room = String(req.params.roomNumber || '').trim();
      if (!room) return res.status(400).json({ error: 'MISSING_ROOM' });

      // สมมติรูปเก็บไว้ที่ /uploads/rooms/<room>.jpg (ปรับให้ตรงกับที่คุณใช้จริง)
      const baseDir = path.join(__dirname, '..', '..', 'uploads', 'rooms');
      const candidates = [
        path.join(baseDir, `${room}.jpg`),
        path.join(baseDir, `${room}.png`),
        path.join(baseDir, `${room}.jpeg`),
      ];
      const file = candidates.find(p => fs.existsSync(p));

      if (!file) return res.status(404).json({ error: 'IMAGE_NOT_FOUND' });
      return res.sendFile(file);
    } catch (e) {
      console.error('room-images error:', e);
      return res.status(500).json({ error: 'SERVER_ERROR' });
    }
  });

  return router;
};
