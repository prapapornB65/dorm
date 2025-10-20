// routes/owner/tenant.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();
  const isPgPromise = typeof db.any === 'function';
  const qAny  = (t, p=[]) => isPgPromise ? db.any(t, p) : db.query(t, p).then(r => r.rows);
  const qOne  = (t, p=[]) => isPgPromise ? db.oneOrNone(t, p) : db.query(t, p).then(r => r.rows[0] || null);

  // ตรวจ buildingId จาก path/query
  const parseIntPos = v => { const n = Number(v); return Number.isInteger(n) && n > 0 ? n : null; };
  const ensureBuildingId = (req, res, next) => {
    const b = parseIntPos(req.params.id ?? req.params.buildingId ?? req.query.buildingId);
    if (!b) return res.status(400).json({ error: 'invalid buildingId' });
    req.buildingId = b; next();
  };

  // GET /api/owner/building/:id/tenants?status=active|ended&q=<search>&page=1&size=50
  router.get('/building/:id/tenants', ensureBuildingId, async (req, res) => {
    const b = req.buildingId;
    const status = String(req.query.status || '').toLowerCase(); // active|ended|''(ทั้งหมด)
    const q = String(req.query.q || '').trim();
    const page = Math.max(1, parseInt(req.query.page || '1', 10));
    const size = Math.min(200, Math.max(1, parseInt(req.query.size || '50', 10)));
    const offset = (page - 1) * size;

    // เงื่อนไขสถานะ:
    // active = อยู่ปัจจุบัน: Tenant.Status ilike 'active' และ (End IS NULL หรือ End > NOW())
    // ended  = ย้ายออก:      Tenant.Status ilike 'ended'  หรือ End <= NOW()
    // ถ้าไม่ส่ง status = ดึงทั้งหมด
    const statusWhere = [];
    if (status === 'active') {
      statusWhere.push(`(COALESCE(t."Status",'') ILIKE 'active' AND (t."End" IS NULL OR t."End" > NOW()))`);
    } else if (status === 'ended') {
      statusWhere.push(`(COALESCE(t."Status",'') ILIKE 'ended' OR (t."End" IS NOT NULL AND t."End" <= NOW()))`);
    } // else: ไม่กรองสถานะ

    // เงื่อนไขค้นหา
    const searchWhere = [];
    const params = [b];
    if (q) {
      params.push(`%${q}%`);
      searchWhere.push(`(
        t."FirstName" ILIKE $2 OR t."LastName" ILIKE $2 OR
        (t."FirstName"||' '||t."LastName") ILIKE $2 OR
        t."Email" ILIKE $2 OR t."Phone" ILIKE $2 OR
        t."RoomNumber" ILIKE $2
      )`);
    }

    const wheres = [
      `r."BuildingID" = $1`,
      ...statusWhere,
      ...searchWhere
    ].filter(Boolean).join(' AND ');

    const rows = await qAny(`
      SELECT
        t."TenantID",
        t."FirstName",
        t."LastName",
        t."Email",
        t."Phone",
        t."RoomNumber",
        t."Start",
        t."End",
        COALESCE(t."Status",'') AS "TenantStatus"
      FROM "Tenant" t
      JOIN "Room"   r ON r."RoomNumber" = t."RoomNumber"
      WHERE ${wheres || 'TRUE'}
      ORDER BY r."RoomNumber" ASC, t."TenantID" DESC
      LIMIT ${size} OFFSET ${offset}
    `, params);

    // รวม count (เพื่อหน้าเพจ/แท็บ)
    const cnt = await qOne(`
      SELECT COUNT(*)::int AS count
      FROM "Tenant" t
      JOIN "Room"   r ON r."RoomNumber" = t."RoomNumber"
      WHERE ${wheres || 'TRUE'}
    `, params);

    res.json({
      page, size, total: cnt?.count || 0,
      items: rows.map(x => ({
        TenantID: x.TenantID,
        FullName: (x.FirstName || x.LastName)
          ? `${x.FirstName || ''} ${x.LastName || ''}`.trim()
          : (x.Email || ''),
        FirstName: x.FirstName,
        LastName: x.LastName,
        Email: x.Email,
        Phone: x.Phone,
        RoomNumber: x.RoomNumber,
        Start: x.Start,
        End: x.End,
        TenantStatus: x.TenantStatus
      }))
    });
  });

  // นับผู้เช่า (active) สำหรับการ์ดบนแดชบอร์ด
  router.get('/building/:id/tenant-count', ensureBuildingId, async (req, res) => {
    const b = req.buildingId;
    const row = await qOne(`
      SELECT COUNT(*)::int AS count
      FROM "Tenant" t
      JOIN "Room" r ON r."RoomNumber" = t."RoomNumber"
      WHERE r."BuildingID" = $1
        AND COALESCE(t."Status",'') ILIKE 'active'
        AND (t."End" IS NULL OR t."End" > NOW())
    `, [b]);
    res.json({ count: row?.count || 0 });
  });

  return router;
};
