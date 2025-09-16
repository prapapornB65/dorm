const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /api/building/:buildingId/monthly-income
  router.get('/building/:buildingId/monthly-income', async (req, res) => {
    const buildingId = parseInt(req.params.buildingId);
    try {
      const totalBalance = await db.one(`
        SELECT COALESCE(SUM(w."Balance"), 0) AS total_balance
        FROM "Wallet" w
        JOIN "Tenant" t ON w."TenantID" = t."TenantID"
        JOIN "Room" r ON t."RoomNumber" = r."RoomNumber"
        WHERE r."BuildingID" = $1
      `, [buildingId]);

      const payments = await db.any(`
        SELECT 
          CONCAT(t."FirstName",' ',t."LastName") AS tenantName,
          p."TotalAmount" AS totalAmount,
          TO_CHAR(p."PaymentDate",'YYYY-MM-DD') AS paymentDate,
          p."Status" AS status
        FROM "Payment" p
        JOIN "Tenant" t ON p."TenantID" = t."TenantID"
        JOIN "Room" r ON t."RoomNumber" = r."RoomNumber"
        WHERE r."BuildingID" = $1
          AND DATE_PART('month', p."PaymentDate") = DATE_PART('month', CURRENT_DATE)
          AND DATE_PART('year', p."PaymentDate") = DATE_PART('year', CURRENT_DATE)
      `, [buildingId]);

      res.json({ totalBalance: totalBalance.total_balance, payments });
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลรายรับต่อเดือน' });
    }
  });

  return router;
};
