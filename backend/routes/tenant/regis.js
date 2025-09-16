// routes/regis.js
const express = require('express');
const bcrypt  = require('bcryptjs');

module.exports = (db) => {
  const router = express.Router();

  // POST /api/tenant/register
  router.post('/tenant/register', async (req, res) => {
    try {
      const {
        firstName, lastName, citizenID, birthDate,
        email, phone, username, password, roomNumber
      } = req.body;

      if (!username || !email || !password) {
        return res.status(400).json({ success:false, message:'กรุณากรอกข้อมูลให้ครบ' });
      }
      if (password.length < 8) {
        return res.status(400).json({ success:false, message:'รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร' });
      }

      // กัน email/username ซ้ำ
      const exist = await db.oneOrNone(
        `SELECT 1 FROM "Tenant" WHERE "Username"=$1 OR "Email"=$2`,
        [username, email]
      );
      if (exist) return res.status(409).json({ success:false, message:'บัญชีนี้มีผู้ใช้งานแล้ว' });

      const hashed = await bcrypt.hash(password, 12);

      // ✅ สมัครผู้เช่า
      const result = await db.one(`
        INSERT INTO "Tenant"
          ("FirstName","LastName","CitizenID","BirthDate","Email","Phone","Username","Password","RoomNumber")
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
        RETURNING "TenantID","FirstName","LastName","Email","RoomNumber"
      `, [firstName, lastName, citizenID, birthDate, email, phone, username, hashed, roomNumber]);

      // ✅ กันคำขอ pending ซ้ำ (อีเมลเดียว/ห้องเดียว)
      const duplicateApproval = await db.oneOrNone(`
        SELECT 1 FROM public."TenantApproval"
        WHERE "Email"=$1 AND "RoomNumber"=$2 AND "Status"='pending'
      `, [result.Email, result.RoomNumber]);
      if (!duplicateApproval) {
        // ✅ สร้างคำขออนุมัติให้ Owner เห็นที่หน้า approval_page
        await db.one(`
          INSERT INTO public."TenantApproval"
            ("TenantID","RoomNumber","FullName","Email")
          VALUES ($1,$2,$3,$4)
          RETURNING "ApprovalID"
        `, [
          result.TenantID,
          result.RoomNumber,
          `${result.FirstName} ${result.LastName}`.trim(),
          result.Email
        ]);
      }

      // ✅ ตอบกลับแบบไม่ล็อกอินใด ๆ
      return res.status(200).json({
        success: true,
        tenantId: result.TenantID,
        message: 'สมัครสำเร็จและส่งคำขออนุมัติแล้ว — กรุณารอเจ้าของหออนุมัติ'
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ success:false, message: err.message });
    }
  });

  return router;
};
