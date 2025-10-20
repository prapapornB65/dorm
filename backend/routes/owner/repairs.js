// backend/routes/owner/repairs.js
const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');

// ✅ รวม status เดียวที่หัวไฟล์ (เพิ่ม 'rejected')
const VALID = new Set(['new', 'in_progress', 'done', 'cancelled', 'rejected']);

const uploadDir = path.join(__dirname, '..', '..', 'uploads', 'repairs');
fs.mkdirSync(uploadDir, { recursive: true });
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, uploadDir),
  filename: (_req, file, cb) => {
    const ts = Date.now();
    const ext = path.extname(file.originalname || '').toLowerCase() || '.jpg';
    cb(null, `repair_${ts}${ext}`);
  },
});
const upload = multer({ storage });

module.exports = (db, requireAuth, requireOwner) => {
  const router = express.Router();

  // -------- DEBUG MIDDLEWARE --------
  router.use((req, res, next) => {
    const tag = `[owner/repairs] ${req.method} ${req.originalUrl}`;
    console.time(tag);
    console.log(tag, 'headers.auth=', req.headers.authorization ? 'present' : 'missing');
    res.on('finish', () => console.timeEnd(tag));
    next();
  });

  // quick health
  router.get('/health', (_req, res) => res.json({ ok: true, scope: 'owner/repairs' }));

  // ตรวจสิทธิ์ว่า request นี้เป็นของ owner คนนี้จริง
  async function assertOwnerCanSeeRequest(req, res, next) {
    const rid = parseInt(req.params.requestId || req.params.id, 10);
    if (!Number.isInteger(rid) || rid <= 0) {
      return res.status(400).json({ error: 'bad_requestId' });
    }
    try {
      const row = await db.oneOrNone(
        `
        SELECT b."OwnerID"
          FROM "RepairRequest" rr
     LEFT JOIN "Tenant"   t ON rr."TenantID" = t."TenantID"
     -- ✅ ใช้เลขห้องจากคำขอซ่อม
     LEFT JOIN "Room"     r ON rr."RoomNumber" = r."RoomNumber"
     LEFT JOIN "Building" b ON r."BuildingID" = b."BuildingID"
         WHERE rr."RequestID" = $1
        `,
        [rid]
      );
      if (!row) return res.status(404).json({ error: 'request_not_found' });
      if (!req.owner || +req.owner.id !== +row.OwnerID) {
        return res.status(403).json({ error: 'not_your_request' });
      }
      next();
    } catch (e) {
      console.error('[owner/repairs] assertOwnerCanSeeRequest', e);
      res.status(500).json({ error: 'OWNER_CHECK_FAILED' });
    }
  }

  // ===== 1) ทั้งหมดของ owner =====
  // GET /repairs?status=...&month=YYYY-MM&q=...
  router.get('/repairs', requireAuth, requireOwner, async (req, res) => {
    try {
      const status = String(req.query.status || 'all').toLowerCase();
      const month  = (req.query.month || '').toString();
      const q      = (req.query.q || '').toString().trim();

      const conds = ['b."OwnerID" = $/ownerId/'];
      const params = { ownerId: req.owner.id };

      if (VALID.has(status)) { conds.push(`rr."Status" = $/status/`); params.status = status === 'rejected' ? 'cancelled' : status; }
      if (/^\d{4}-\d{2}$/.test(month)) { conds.push(`to_char(rr."RequestDate",'YYYY-MM') = $/month/`); params.month = month; }
      if (q) { conds.push(`(rr."Equipment" ILIKE $/q/ OR rr."IssueDetail" ILIKE $/q/ OR rr."RoomNumber" ILIKE $/q/)`); params.q = `%${q}%`; }

      const where = `WHERE ${conds.join(' AND ')}`;

      const rows = await db.manyOrNone(
        `
        SELECT rr."RequestID", rr."TenantID", rr."RoomNumber", rr."Equipment",
               rr."IssueDetail", rr."RequestDate", rr."Status", rr."ImagePath",
               rr."Phone", rr."Additional",
                r."RoomNumber" AS "RoomNum",
               b."BuildingID", b."BuildingName",
               t."FirstName", t."LastName"
          FROM "RepairRequest" rr
     LEFT JOIN "Tenant"   t ON rr."TenantID" = t."TenantID"
     -- ✅ ใช้เลขห้องจากคำขอซ่อม
     LEFT JOIN "Room"     r ON rr."RoomNumber" = r."RoomNumber"
     LEFT JOIN "Building" b ON r."BuildingID" = b."BuildingID"
          ${where}
      ORDER BY rr."RequestDate" DESC, rr."RequestID" DESC
        `,
        params
      );

      res.json({ items: rows });
    } catch (e) {
      console.error('[owner/repairs:list]', e);
      res.status(500).json({ error: 'FAILED_LIST_REPAIRS' });
    }
  });

  // ===== 2) ตามตึก =====
  // GET /building/:buildingId/repairs?status=...&month=...&q=...
  router.get('/building/:buildingId/repairs', requireAuth, requireOwner, async (req, res) => {
    try {
      const buildingId = parseInt(req.params.buildingId, 10);
      if (!Number.isInteger(buildingId) || buildingId <= 0) {
        return res.status(400).json({ error: 'bad_buildingId' });
      }

      const b = await db.oneOrNone(`SELECT "OwnerID" FROM "Building" WHERE "BuildingID"=$1`, [buildingId]);
      if (!b) return res.status(404).json({ error: 'building_not_found' });
      if (+b.OwnerID !== +req.owner.id) return res.status(403).json({ error: 'not_your_building' });

      const status = String(req.query.status || 'all').toLowerCase();
      const month  = (req.query.month || '').toString();
      const q      = (req.query.q || '').toString().trim();

      const conds = [`b."BuildingID" = $/buildingId/`];
      const params = { buildingId };

      if (VALID.has(status)) { conds.push(`rr."Status" = $/status/`); params.status = status === 'rejected' ? 'cancelled' : status; }
      if (/^\d{4}-\d{2}$/.test(month)) { conds.push(`to_char(rr."RequestDate",'YYYY-MM')=$/month/`); params.month = month; }
      if (q) { conds.push(`(rr."Equipment" ILIKE $/q/ OR rr."IssueDetail" ILIKE $/q/ OR rr."RoomNumber" ILIKE $/q/)`); params.q = `%${q}%`; }

      const where = `WHERE ${conds.join(' AND ')}`;

      const rows = await db.manyOrNone(
        `
        SELECT rr."RequestID", rr."TenantID", rr."RoomNumber", rr."Equipment",
               rr."IssueDetail", rr."RequestDate", rr."Status", rr."ImagePath",
               rr."Phone", rr."Additional",
                r."RoomNumber" AS "RoomNum",
               b."BuildingID", b."BuildingName",
               t."FirstName", t."LastName"
          FROM "RepairRequest" rr
     LEFT JOIN "Tenant"   t ON rr."TenantID" = t."TenantID"
     -- ✅ ใช้เลขห้องจากคำขอซ่อม
     LEFT JOIN "Room"     r ON rr."RoomNumber" = r."RoomNumber"
     LEFT JOIN "Building" b ON r."BuildingID" = b."BuildingID"
          ${where}
      ORDER BY rr."RequestDate" DESC, rr."RequestID" DESC
        `,
        params
      );

      res.json({ items: rows });
    } catch (e) {
      console.error('[owner/repairs:listByBuilding]', e);
      res.status(500).json({ error: 'FAILED_LIST_REPAIRS' });
    }
  });

  // ===== 3) อัปเดตสถานะ =====
  // PATCH /repairs/:requestId/status  body: { status: 'new'|'in_progress'|'done'|'cancelled'|'rejected' }
  router.patch('/repairs/:requestId/status', requireAuth, requireOwner, assertOwnerCanSeeRequest, async (req, res) => {
    try {
      let status = String(req.body?.status || '').toLowerCase();
      // map alias
      if (status === 'rejected') status = 'cancelled';
      if (!VALID.has(status)) return res.status(400).json({ error: 'bad_status' });

      const row = await db.one(
        `UPDATE "RepairRequest" SET "Status"=$2 WHERE "RequestID"=$1 RETURNING "RequestID","Status"`,
        [parseInt(req.params.requestId, 10), status]
      );

      res.json({ ok: true, requestId: row.RequestID, status: row.Status });
    } catch (e) {
      console.error('[owner/repairs:updateStatus]', e);
      res.status(500).json({ error: 'FAILED_UPDATE_STATUS' });
    }
  });

  // ===== 4) อัปโหลดรูป =====
  // POST /repairs/:requestId/photo  (form-data: image)
  router.post('/repairs/:requestId/photo', requireAuth, requireOwner, assertOwnerCanSeeRequest, upload.single('image'), async (req, res) => {
    try {
      if (!req.file) return res.status(400).json({ error: 'image_required' });
      const urlPath = `/uploads/repairs/${req.file.filename}`;
      await db.none(
        `UPDATE "RepairRequest" SET "ImagePath"=$2 WHERE "RequestID"=$1`,
        [parseInt(req.params.requestId, 10), urlPath]
      );
      res.status(201).json({ ok: true, imagePath: urlPath });
    } catch (e) {
      console.error('[owner/repairs:photo]', e);
      res.status(500).json({ error: 'FAILED_UPLOAD_PHOTO' });
    }
  });

  return router;
};
