// backend/routes/owner/uploadQR.js
const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');

module.exports = (db) => {
  const router = express.Router();

  // โฟลเดอร์ปลายทางที่ server.js เสิร์ฟด้วย app.use('/uploads', ...)
  const destDir = path.join(__dirname, '..', '..', 'uploads', 'qr_codes');
  if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });

  // ตั้ง storage ให้ตั้งชื่อไฟล์ใหม่เลย
  const storage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, destDir),
    filename: (req, file, cb) => {
      const { ownerId, buildingId } = req.body;
      const ext = path.extname(file.originalname || '.png').toLowerCase();
      const fileName = `qr_owner${ownerId}_building${buildingId}_${Date.now()}${ext}`;
      cb(null, fileName); // <- ตัวนี้จะไปอยู่ที่ req.file.filename
    },
  });

  const upload = multer({ storage });

  // POST /api/upload-qr
  router.post('/upload-qr', upload.single('qrImage'), async (req, res) => {
    try {
      const { ownerId, buildingId } = req.body;
      if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
      if (!ownerId || !buildingId) {
        return res.status(400).json({ error: 'Missing ownerId or buildingId' });
      }

      const savedName = req.file.filename;              // <- ใช้ชื่อนี้
      const savedPath = path.join(destDir, savedName);
      console.log('[upload-qr] saved =>', savedPath, 'exists=', fs.existsSync(savedPath));

      // ใช้ host ตามคำขอจริง (แก้ปัญหา localhost/192.168)
      const base = `${req.protocol}://${req.get('host')}`;
      const qrUrl = `${base}/uploads/qr_codes/${savedName}`;

      await db.none(
        `UPDATE "Building" SET "QrCodeUrl"=$1 WHERE "OwnerID"=$2 AND "BuildingID"=$3`,
        [qrUrl, ownerId, buildingId]
      );

      return res.json({ success: true, qrUrl });
    } catch (err) {
      console.error('Upload QR Error:', err);
      return res.status(500).json({ error: 'Internal Server Error' });
    }
  });

  return router;
};
