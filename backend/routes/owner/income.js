// routes/owner/income.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // ---------------------------------------------------------------------------
  // GET /api/owner/building/:buildingId/monthly-income-summary?months=12
  // คืน: { months: [{ ym: 'YYYY-MM', total: number }, ...] }
  // ---------------------------------------------------------------------------
  router.get('/building/:buildingId/monthly-income-summary', async (req, res) => {
    const buildingId = parseInt(req.params.buildingId, 10);
    let months = parseInt(String(req.query.months || '12'), 10);
    if (!Number.isFinite(buildingId)) return res.status(400).json({ error: 'invalid buildingId' });
    if (Number.isNaN(months)) months = 12;
    months = Math.max(1, Math.min(36, months));

    try {
      const rows = await db.any(`
        WITH m AS (SELECT generate_series(0, $2::int - 1) AS off),
        series AS (
          SELECT
            to_char(date_trunc('month', (date_trunc('month', CURRENT_DATE) - (off || ' months')::interval)), 'YYYY-MM') AS month_key,
            date_trunc('month', (date_trunc('month', CURRENT_DATE) - (off || ' months')::interval)) AS start_at,
            (date_trunc('month', (date_trunc('month', CURRENT_DATE) - (off || ' months')::interval)) + interval '1 month') AS end_at
          FROM m
        )
        SELECT
          s.month_key AS ym,
          COALESCE((
            SELECT SUM(p."TotalAmount")::float8
            FROM public."Room" r
            JOIN public."Tenant" t  ON t."RoomNumber" = r."RoomNumber"
            JOIN public."Payment" p ON p."TenantID"   = t."TenantID"
            WHERE r."BuildingID" = $1::int
              AND p."PaymentDate" >= s.start_at
              AND p."PaymentDate" <  s.end_at
          ), 0) AS total
        FROM series s
        ORDER BY s.start_at ASC
      `, [buildingId, months]);

      res.json({ months: rows });
    } catch (err) {
      console.error('monthly-income-summary error:', err);
      res.status(500).json({ error: 'SERVER_ERROR' });
    }
  });

  // ---------------------------------------------------------------------------
  // GET /api/owner/building/:buildingId/monthly-income
  // รวมยอดเดือนปัจจุบัน: { totalBalance: number }
  // ---------------------------------------------------------------------------
  router.get('/building/:buildingId/monthly-income', async (req, res) => {
    const buildingId = parseInt(req.params.buildingId, 10);
    if (!Number.isFinite(buildingId)) return res.status(400).json({ error: 'invalid buildingId' });

    try {
      const row = await db.one(`
        WITH bounds AS (
          SELECT
            date_trunc('month', CURRENT_DATE) AS start_at,
            (date_trunc('month', CURRENT_DATE) + interval '1 month') AS end_at
        )
        SELECT
          COALESCE(SUM(p."TotalAmount")::float8, 0) AS "totalBalance"
        FROM bounds b
        JOIN public."Tenant"  t ON TRUE
        JOIN public."Room"    r ON t."RoomNumber" = r."RoomNumber" AND r."BuildingID" = $1
        JOIN public."Payment" p ON p."TenantID"   = t."TenantID"
                               AND p."PaymentDate" >= b.start_at
                               AND p."PaymentDate" <  b.end_at
      `, [buildingId]);

      res.json({ totalBalance: row.totalBalance });
    } catch (err) {
      console.error('monthly-income error:', err);
      res.status(500).json({ error: 'SERVER_ERROR' });
    }
  });

  // ---------------------------------------------------------------------------
  // GET /api/owner/building/:buildingId/monthly-income-detail?year=YYYY&month=M
  // คืน: { total: number, items: [{ id, PaidAt, roomNumber, PayerName, Amount, Type }, ...] }
  // ---------------------------------------------------------------------------
  router.get('/building/:buildingId/monthly-income-detail', async (req, res) => {
    const buildingId = parseInt(req.params.buildingId, 10);
    const year = parseInt(String(req.query.year ?? ''), 10);
    const month = parseInt(String(req.query.month ?? ''), 10);

    if (!Number.isFinite(buildingId) || !Number.isFinite(year) || !Number.isFinite(month) || month < 1 || month > 12) {
      return res.status(400).json({ error: 'invalid params' });
    }

    try {
      const items = await db.any(`
       SELECT
  p."PaymentID" AS id,
  p."PaymentDate" AS "PaidAt",
  r."RoomNumber"  AS "roomNumber",
  COALESCE(
    NULLIF(trim(COALESCE(tn."FirstName",'') || ' ' || COALESCE(tn."LastName",'')),''),
    tn."Email",
    ''
  ) AS "PayerName",
  COALESCE(p."TotalAmount"::float8,0) AS "Amount",
  COALESCE(p."PaymentMethod",'')     AS "Type"
FROM public."Payment" p
JOIN public."Tenant" tn ON tn."TenantID" = p."TenantID"
JOIN public."Room"   r  ON r."RoomNumber" = tn."RoomNumber"
WHERE r."BuildingID" = $1::int
  AND p."PaymentDate" >= make_date($2::int,$3::int,1)
  AND p."PaymentDate" <  (make_date($2::int,$3::int,1) + interval '1 month')
ORDER BY p."PaymentDate" DESC

      `, [buildingId, year, month]);

      const total = items.reduce((s, r) => s + (Number(r.Amount) || 0), 0);
      res.json({ total, items });
    } catch (e) {
      console.error('monthly-income-detail error:', e);
      res.status(500).json({ error: 'SERVER_ERROR' });
    }
  });

  // ---------------------------------------------------------------------------
  // (ออปชัน) GET /api/owner/building/:buildingId/payments?month=YYYY-MM
  // คืน: { month: 'YYYY-MM', items: [{ id, roomNumber, amount, date }, ...] }
  // ---------------------------------------------------------------------------
  router.get('/building/:buildingId/payments', async (req, res) => {
    const buildingId = parseInt(req.params.buildingId, 10);
    const monthStr = String(req.query.month || '').trim(); // '2025-10'
    if (!Number.isFinite(buildingId)) return res.status(400).json({ error: 'invalid buildingId' });
    if (!/^\d{4}-\d{2}$/.test(monthStr)) return res.status(400).json({ error: 'invalid month' });

    const [yStr, mStr] = monthStr.split('-');
    const y = parseInt(yStr, 10);
    const m = parseInt(mStr, 10);

    try {
      const items = await db.any(`
        WITH bounds AS (
          SELECT
            make_timestamptz($2, $3, 1, 0, 0, 0, 'Asia/Bangkok') AS start_at,
            (make_timestamptz($2, $3, 1, 0, 0, 0, 'Asia/Bangkok') + interval '1 month') AS end_at
        )
        SELECT
          p."PaymentID" AS id,
          r."RoomNumber" AS "roomNumber",
          COALESCE(p."TotalAmount"::float8,0) AS amount,
          p."PaymentDate" AS date
        FROM bounds b
        JOIN public."Tenant"  t ON TRUE
        JOIN public."Room"    r ON r."RoomNumber" = t."RoomNumber" AND r."BuildingID" = $1
        JOIN public."Payment" p ON p."TenantID"   = t."TenantID"
                               AND p."PaymentDate" >= b.start_at
                               AND p."PaymentDate" <  b.end_at
        ORDER BY date ASC
      `, [buildingId, y, m]);

      res.json({ month: monthStr, items });
    } catch (e) {
      console.error('payments list error:', e);
      res.status(500).json({ error: 'SERVER_ERROR' });
    }
  });

  return router;
};
