// ของเดิม: POST /upload-slip-image (บันทึกรูป slip) — คง path เดิมไว้
const express = require('express');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');

module.exports = (_db) => {
  const router = express.Router();

  const uploadDir = path.join(__dirname, '..', '..', 'uploads');
  if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

  const storage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, uploadDir),
    filename: (_req, file, cb) => {
      const uniqueName = Date.now() + '_' + file.originalname; // (แนะนำภายหลังเปลี่ยนเป็น uuid + ตรวจ mimetype)
      cb(null, uniqueName);
    }
  });

  const upload = multer({ storage });

  // POST /api/upload-slip-image
  router.post('/upload-slip-image', upload.single('file'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: true, message: 'No file uploaded' });
    const fileUrl = `http://${process.env.HOST_IP}/uploads/${req.file.filename}`;
    res.json({ error: false, message: 'Upload success', fileUrl, filename: req.file.filename });
  });

  return router;
};
