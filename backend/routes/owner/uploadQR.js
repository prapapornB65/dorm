const express = require('express');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');

module.exports = (db) => {
  const router = express.Router();

  const destDir = path.join(process.cwd(), 'backend', 'uploads', 'qr_codes');
  if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });

  const upload = multer({ dest: destDir });

  // POST /api/upload-qr
  router.post('/upload-qr', upload.single('qrImage'), async (req, res) => {
    try {
      const { ownerId, buildingId } = req.body;
      const file = req.file;

      if (!file) return res.status(400).json({ error: 'No file uploaded' });
      if (!ownerId || !buildingId) return res.status(400).json({ error: 'Missing ownerId or buildingId' });

      const fileExt = path.extname(file.originalname);
      const newFileName = `qr_owner${ownerId}_building${buildingId}${fileExt}`;
      const newPath = path.join(destDir, newFileName);

      fs.renameSync(file.path, newPath);

      const qrUrl = `http://${process.env.HOST_IP}:${process.env.HOST_PORT}/uploads/qr_codes/${newFileName}`;

      await db.none(
        `UPDATE "Building" SET "QrCodeUrl"=$1 WHERE "OwnerID"=$2 AND "BuildingID"=$3`,
        [qrUrl, ownerId, buildingId]
      );

      res.json({ success: true, qrUrl });
    } catch (error) {
      console.error('Upload QR Error:', error);
      res.status(500).json({ error: 'Internal Server Error' });
    }
  });

  return router;
};
