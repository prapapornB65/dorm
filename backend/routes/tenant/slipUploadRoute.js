// routes/tenant/slipUploadRoute.js
const express = require('express');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');

module.exports = (db) => {
  const router = express.Router();

  // ===================== 1) เตรียมโฟลเดอร์อัปโหลด =====================
  const uploadRoot = path.join(__dirname, '..', '..', 'uploads');
  const slipDir    = path.join(uploadRoot, 'slips');
  fs.mkdirSync(slipDir, { recursive: true });

  // ===================== 2) ตั้งค่า Multer (กันค้าง/กันผิดประเภท) =====================
  const storage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, slipDir),
    filename: (_req, file, cb) => {
      const safe = file.originalname.replace(/[^\w.\-]+/g, '_');
      cb(null, `slip_${Date.now()}_${safe}`);
    }
  });

  const upload = multer({
    storage,
    limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
    fileFilter: (_req, file, cb) => {
      const ok = /image\/(jpeg|png|webp|jpg)/i.test(file.mimetype);
      cb(ok ? null : new multer.MulterError('LIMIT_UNEXPECTED_FILE', 'file'), ok);
    }
  });

  // Helper: สร้าง URL ไฟล์แบบเต็ม (รองรับพร็อกซี่)
  function buildPublicUrl(req, relativePath) {
    // ถ้าแอปคุณอยู่หลัง reverse proxy ให้ตั้ง trust proxy ที่ server.js ด้วย: app.set('trust proxy', 1)
    const proto = (req.headers['x-forwarded-proto'] || req.protocol || 'http').split(',')[0];
    const host  = (req.headers['x-forwarded-host']  || req.get('host'));
    return `${proto}://${host}${relativePath}`;
  }

  // ===================== 3) อัปโหลดรูปสลิป =====================
  // POST /api/upload-slip-image  (field: 'file')
  router.post('/upload-slip-image', (req, res) => {
    upload.single('file')(req, res, (err) => {
      // จัดการ error ของ Multer ให้ตอบกลับเสมอ → จะไม่ค้าง
      if (err instanceof multer.MulterError) {
        // ชนิดไฟล์ไม่ตรง / ขนาดเกิน / field ผิด ฯลฯ
        const codeMap = {
          LIMIT_FILE_SIZE:      'File too large',
          LIMIT_UNEXPECTED_FILE:'Invalid image type or wrong field name',
        };
        const msg = codeMap[err.code] || 'Upload error';
        return res.status(400).json({ error: true, message: msg, code: err.code });
      } else if (err) {
        return res.status(500).json({ error: true, message: 'Upload failed' });
      }

      if (!req.file) {
        return res.status(400).json({ error: true, message: 'No file uploaded' });
      }

      // NOTE:
      // ให้เสิร์ฟ static ใน server.js ระดับแอป:
      //   app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
      // เพื่อให้ path นี้ใช้งานได้: /uploads/slips/xxx
      const publicPath = `/uploads/slips/${req.file.filename}`;
      const fileUrl = buildPublicUrl(req, publicPath);

      return res.json({
        error: false,
        message: 'Upload success',
        fileUrl,        // เอาตัวนี้ไปเก็บใน DB/แสดงผลฝั่งแอป
        filename: req.file.filename,
        publicPath      // เผื่อเก็บ path relative
      });
    });
  });

  // ===================== 4) บันทึก Payment + SlipUpload (transaction) =====================
  // POST /api/slipupload/:tenantId
  // body: { RoomNumber, ImagePath, SenderName, Note, UploadDate, amount, bank, status }
  router.post('/slipupload/:tenantId', express.json({ limit: '256kb' }), async (req, res) => {
    const tenantId = Number(req.params.tenantId);
    if (!Number.isInteger(tenantId)) {
      return res.status(400).json({ error: true, message: 'invalid tenantId' });
    }

    const {
      RoomNumber,
      ImagePath,
      SenderName,
      Note,
      UploadDate, // ISO string
      amount,     // number (บาท)
      bank,       // ชื่อธนาคาร (เช่น "กรุงเทพ")
      status      // "verified" | "pending" | ...
    } = req.body || {};

    // ตรวจค่าว่าง
    if (!RoomNumber || !ImagePath || !UploadDate || (amount === undefined) || !bank || !status) {
      return res.status(400).json({ error: true, message: 'missing required fields' });
    }

    // ตรวจชนิดข้อมูล amount ให้ชัด
    const amountNum = Number(amount);
    if (!Number.isFinite(amountNum) || amountNum < 0) {
      return res.status(400).json({ error: true, message: 'invalid amount' });
    }

    // แปลงเวลา
    const when = new Date(UploadDate);
    if (isNaN(when.getTime())) {
      return res.status(400).json({ error: true, message: 'invalid UploadDate' });
    }

    try {
      const result = await db.tx(async (t) => {
        // 1) Insert Payment
        const pay = await t.one(
          `INSERT INTO "Payment"
             ("TenantID","PaymentDate","TotalAmount","PaymentMethod","Status")
           VALUES ($1,$2,$3,$4,$5)
           RETURNING "PaymentID"`,
          [tenantId, when, amountNum, String(bank).trim(), String(status).trim()]
        );

        // 2) Insert SlipUpload + ผูก PaymentID
        const slip = await t.one(
          `INSERT INTO "SlipUpload"
             ("TenantID","RoomNumber","UploadDate","ImagePath","PaymentID","Note","SenderName")
           VALUES ($1,$2,$3,$4,$5,$6,$7)
           RETURNING "SlipID"`,
          [tenantId, RoomNumber, when, ImagePath, pay.PaymentID, Note || null, SenderName || null]
        );

        return { paymentId: pay.PaymentID, slipId: slip.SlipID };
      });

      return res.json({ ok: true, message: 'saved', ...result });
    } catch (e) {
      console.error('[slipupload] ERROR:', e);
      return res.status(500).json({ error: true, message: 'server error saving slip/payment' });
    }
  });

  return router;
};
