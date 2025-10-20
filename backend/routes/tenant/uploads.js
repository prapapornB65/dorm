// routes/tenant/uploads.js
const express = require('express');
const path = require('path');
const multer = require('multer');

module.exports = (db) => {
  const router = express.Router();

  // เตรียม storage (คุณอาจเปลี่ยนไปใช้ safeUpload ที่ผมเสนอได้)
  const uploadFolder = path.join(__dirname, '..', '..', 'uploads');
  const storage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, uploadFolder),
    filename: (_req, file, cb) => {
      const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
      const ext = path.extname(file.originalname);
      cb(null, file.fieldname + '-' + uniqueSuffix + ext);
    },
  });
  const upload = multer({ storage });

  // POST /api/upload-profile
  router.post('/upload-profile', upload.single('image'), async (req, res) => {
    const tenantId = req.body.tenantId;
    const file = req.file;
    if (!tenantId || !file) return res.status(400).json({ error: 'Missing tenantId or image file.' });

    const imageUrl = `http://${process.env.HOST_IP}:${process.env.HOST_PORT}/uploads/${file.filename}`;

    try {
      await db.none(`UPDATE "Tenant" SET "ProfileImage"=$1 WHERE "TenantID"=$2`, [imageUrl, tenantId]);
      res.json({ success: true, imageUrl });
    } catch (e) {
      console.error('❌ DB update error:', e);
      res.status(500).json({ error: 'Database update failed.' });
    }
  });

  // POST /api/slipupload/:tenantId
  router.post('/slipupload/:tenantId', async (req, res) => {
    const tenantId = req.params.tenantId;
    const { RoomNumber, UploadDate, ImagePath, Note, SenderName, amount, bank } = req.body;

    if (!tenantId || !RoomNumber || !ImagePath || !UploadDate || !amount || !bank) {
      return res.status(400).json({ error: true, message: 'ข้อมูลไม่ครบถ้วน' });
    }

    try {
      // กันสลิปซ้ำ (ตาม ImagePath + TenantID)
      const exists = await db.oneOrNone(`
  SELECT "UploadDate" FROM public."SlipUpload"
  WHERE "TenantID"=$1 AND "ImagePath"=$2
`, [tenantId, ImagePath]);

      if (exists) {
        // ✅ ส่ง ISO (หรือจะส่ง epoch ก็ได้)
        return res.status(409).json({
          error: true,
          code: 'DUP_SLIP',
          message: 'สลิปนี้ถูกส่งแล้ว',
          when: new Date(exists.UploadDate).toISOString()   // <── ISO8601
          // หรือส่ง whenEpoch: new Date(exists.UploadDate).getTime()
        });
      }
      // 1) Payment
      const payment = await db.one(`
        INSERT INTO public."Payment" ("TenantID","PaymentDate","TotalAmount","PaymentMethod","Status")
        VALUES ($1,$2,$3,$4,$5) RETURNING "PaymentID"
      `, [tenantId, UploadDate, amount, bank, 'Pending']);

      // 2) SlipUpload
      const slip = await db.one(`
        INSERT INTO public."SlipUpload"
        ("TenantID","RoomNumber","UploadDate","ImagePath","Note","PaymentID","SenderName")
        VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *
      `, [tenantId, RoomNumber, UploadDate, ImagePath, Note || null, payment.PaymentID, SenderName || null]);

      // 3) เติมเงินเข้ากระเป๋า
      await db.none(`
        UPDATE public."Wallet" SET "Balance"="Balance"+$1 WHERE "TenantID"=$2
      `, [amount, tenantId]);

      res.json({ error: false, message: 'บันทึกสลิปเรียบร้อย', slip });
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: true, message: 'เกิดข้อผิดพลาดในการบันทึกสลิป' });
    }
  });

  return router;
};
