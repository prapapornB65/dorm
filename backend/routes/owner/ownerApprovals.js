// routes/owner/ownerApprovals.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // ---------- utils ----------
  function uniqueTimerLabel(base) {
    return `${base}#${Date.now()}#${Math.random().toString(36).slice(2, 7)}`;
  }

  const BASE_SELECT = `
    SELECT
      TA."ApprovalID", TA."TenantID", TA."RoomNumber", TA."FullName", TA."Email",
      TA."Status", TA."Reason", TA."RequestDate",
      TA."ApprovedAt", TA."ApprovedBy",
      (COALESCE(O."FirstName",'') || ' ' || COALESCE(O."LastName",'')) AS "ApproverName",
      R."BuildingID", B."BuildingName", B."OwnerID"
    FROM public."TenantApproval" TA
    JOIN public."Room"     R ON R."RoomNumber"  = TA."RoomNumber"
    JOIN public."Building" B ON B."BuildingID"  = R."BuildingID"
    LEFT JOIN public."Owner" O ON O."OwnerID"   = TA."ApprovedBy"
  `;

  async function getOwnerRowByApproval(t, approvalId) {
    return t.oneOrNone(`
    SELECT B."OwnerID"
    FROM public."TenantApproval" TA
    JOIN public."Room"     R ON R."RoomNumber"  = TA."RoomNumber"
    JOIN public."Building" B ON B."BuildingID"  = R."BuildingID"
    WHERE TA."ApprovalID" = $1
    LIMIT 1
  `, [approvalId]);
  }

  // ========== LIST ==========
  // GET /api/owner/:ownerId/approvals?status=&q=&buildingId=&room=&limit=&offset=
  router.get('/:ownerId/approvals', async (req, res) => {
    const t = uniqueTimerLabel('approvals.list');
    console.time(t);
    res.on('finish', () => console.timeEnd(t));

    const { ownerId } = req.params;
    const { status, q, buildingId, room, limit = 50, offset = 0 } = req.query;

    const where = [`B."OwnerID" = $1`];
    const args = [ownerId];
    let i = 2;

    if (status && ['pending', 'approved', 'rejected'].includes(status)) {
      where.push(`TA."Status" = $${i++}`);
      args.push(status);
    }
    if (q && q.trim() !== '') {
      where.push(`(TA."RoomNumber" ILIKE $${i} OR TA."FullName" ILIKE $${i} OR TA."Email" ILIKE $${i})`);
      args.push(`%${q.trim()}%`);
      i++;
    }
    if (buildingId) { where.push(`R."BuildingID" = $${i++}`); args.push(buildingId); }
    if (room) { where.push(`TA."RoomNumber" = $${i++}`); args.push(room); }

    const lim = Math.min(parseInt(limit, 10) || 50, 200);
    const off = parseInt(offset, 10) || 0;

    try {
      const sql = `${BASE_SELECT}
        WHERE ${where.join(' AND ')}
        ORDER BY TA."RequestDate" DESC
        LIMIT ${lim} OFFSET ${off};`;
      const rows = await db.any(sql, args);
      res.json(rows);
    } catch (e) {
      console.error('GET owner approvals error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ========== SUMMARY ==========
  // GET /api/owner/:ownerId/approvals/summary?buildingId=
  router.get('/:ownerId/approvals/summary', async (req, res) => {
    const { ownerId } = req.params;
    const { buildingId } = req.query;

    const where = [`B."OwnerID" = $1`];
    const args = [ownerId];
    let i = 2;
    if (buildingId) { where.push(`R."BuildingID" = $${i++}`); args.push(buildingId); }

    try {
      const rows = await db.any(`
        SELECT
          COUNT(*)::int AS total,
          COUNT(*) FILTER (WHERE TA."Status"='pending')::int  AS pending,
          COUNT(*) FILTER (WHERE TA."Status"='approved')::int AS approved,
          COUNT(*) FILTER (WHERE TA."Status"='rejected')::int AS rejected
        FROM public."TenantApproval" TA
        JOIN public."Room"     R ON R."RoomNumber" = TA."RoomNumber"
        JOIN public."Building" B ON B."BuildingID" = R."BuildingID"
        WHERE ${where.join(' AND ')};
      `, args);
      res.json(rows[0] || { total: 0, pending: 0, approved: 0, rejected: 0 });
    } catch (e) {
      console.error('GET owner approvals summary error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ========== GET BY ID ==========
  // GET /api/owner/:ownerId/approvals/:approvalId
  router.get('/:ownerId/approvals/:approvalId', async (req, res) => {
    const { ownerId, approvalId } = req.params;
    try {
      const rows = await db.any(`
        ${BASE_SELECT}
        WHERE B."OwnerID"=$1 AND TA."ApprovalID"=$2
        LIMIT 1;
      `, [ownerId, approvalId]);
      if (!rows.length) return res.status(404).json({ error: 'NOT_FOUND' });
      res.json(rows[0]);
    } catch (e) {
      console.error('GET owner approval by id error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // ========== APPROVE ==========
  async function approveHandler(req, res) {
    const tlabel = uniqueTimerLabel('approvals.approve');
    console.time(tlabel);
    res.on('finish', () => console.timeEnd(tlabel));

    const { ownerId, approvalId } = req.params;

    try {
      const result = await db.tx(async t => {
        // 1) โหลดคำขอ + ตรวจสิทธิ์ owner + ล็อกแถว approval
        const ap = await t.oneOrNone(`
          SELECT TA."ApprovalID", TA."TenantID", TA."RoomNumber", TA."FullName",
                 TA."Email", TA."Status", TA."Payload",
                 R."BuildingID"
          FROM public."TenantApproval" TA
          JOIN public."Room"     R ON R."RoomNumber" = TA."RoomNumber"
          JOIN public."Building" B ON B."BuildingID" = R."BuildingID"
          WHERE B."OwnerID" = $1
            AND TA."ApprovalID" = $2
          FOR UPDATE
        `, [ownerId, approvalId]);

        if (!ap) return { http: 404, error: 'NOT_FOUND_OR_FORBIDDEN' };
        if (ap.Status !== 'pending') return { http: 409, error: `ALREADY_${ap.Status.toUpperCase()}` };

        // 2) จับห้องแบบ atomic: ว่างเท่านั้น
        const updatedRoom = await t.oneOrNone(`
          UPDATE public."Room"
          SET "Status"='occupied'
          WHERE "RoomNumber" = $1
            AND "BuildingID" = $2
            AND "Status" IN ('available','ว่าง')
          RETURNING "RoomNumber","Status"
        `, [ap.RoomNumber, ap.BuildingID]);

        if (!updatedRoom) {
          const cur = await t.oneOrNone(`
            SELECT "Status" FROM public."Room"
            WHERE "RoomNumber"=$1 AND "BuildingID"=$2
          `, [ap.RoomNumber, ap.BuildingID]);
          return { http: 409, error: cur ? `ROOM_${cur.Status.toUpperCase()}` : 'ROOM_NOT_FOUND' };
        }

        // 3) upsert Tenant + เปิดสัญญาวันนี้
        const p = ap.Payload || {};
        const [firstName, ...rest] = (ap.FullName || '').trim().split(/\s+/);
        const lastName = rest.join(' ') || null;

        if (ap.TenantID) {
          await t.none(`
            UPDATE public."Tenant"
SET "FirstName"=$2, "LastName"=$3,
    "CitizenID"=$4, "BirthDate"=$5,
    "Email"=$6, "Phone"=$7, "UserName"=$8, "Password"=$9,
    "RoomNumber"=$10,
    "Start"=COALESCE("Start", CURRENT_DATE), "End"=NULL,
    "Status"='approved', "ApprovedAt"=NOW(), "ApprovedByOwnerID"=$11
WHERE "TenantID"=$1

          `, [
            ap.TenantID,
            firstName || null, lastName,
            p.citizenID ?? null, p.birthDate ?? null,
            ap.Email, p.phone ?? null, p.username ?? null, p.passwordHash ?? null,
            ap.RoomNumber,
            ownerId
          ]);
        } else {
          await t.none(`
            INSERT INTO public."Tenant"
              ("FirstName","LastName","CitizenID","BirthDate","Email","Phone","UserName","Password",
               "RoomNumber","Start","End","ProfileImage","Role","FirebaseUID")
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8, $9, CURRENT_DATE, NULL, NULL, 'tenant', NULL)
          `, [
            firstName || null, lastName,
            p.citizenID ?? null, p.birthDate ?? null,
            ap.Email, p.phone ?? null, p.username ?? null, p.passwordHash ?? null,
            ap.RoomNumber, ownerId
          ]);
        }

        // 4) ปิดคำขอเป็น approved (เฉพาะถ้ายัง pending)
        const approved = await t.oneOrNone(`
          UPDATE public."TenantApproval"
          SET "Status"='approved', "Reason"=NULL,
              "ApprovedAt"=NOW(), "ApprovedBy"=$2
          WHERE "ApprovalID"=$1 AND "Status"='pending'
          RETURNING "ApprovalID"
        `, [approvalId, ownerId]);

        if (!approved) {
          // rollback ห้อง (edge case)
          await t.none(`
            UPDATE public."Room"
            SET "Status"='available'
            WHERE "RoomNumber"=$1 AND "BuildingID"=$2 AND "Status"='occupied'
          `, [ap.RoomNumber, ap.BuildingID]);
          return { http: 409, error: 'APPROVAL_STATUS_CHANGED' };
        }

        await t.none(`
  INSERT INTO public."Wallet"("TenantID","Balance","UpdatedAt")
  VALUES ($1, 0, NOW())
  ON CONFLICT ("TenantID") DO NOTHING
`, [tenant.TenantID]);

        await t.none(`
  INSERT INTO public."UnitBalance"("TenantID","ElectricUnit","WaterUnit","UpdatedAt")
  VALUES ($1, 0, 0, NOW())
  ON CONFLICT ("TenantID") DO NOTHING
`, [tenant.TenantID]);

        // ผูกผู้เช่ากับห้องให้ชัดเจน (หากมีคอลัมน์นี้)
        await t.none(`
  UPDATE public."Room"
  SET "CurrentTenantID"=$1, "Status"='occupied', "UpdatedAt"=NOW()
  WHERE "RoomNumber"=$2
`, [tenant.TenantID, ap.RoomNumber]);

        return { ok: true, room: updatedRoom };
      });


      if (result.http) return res.status(result.http).json({ error: result.error });
      return res.json({ approved: true, room: result.room });
    } catch (e) {
      console.error('approve error', e);
      return res.status(500).json({ error: 'DB_ERROR' });
    }
  }

  // --- alias (POST) ให้แมป ownerId จาก approval แล้วเรียก approveHandler เดิม ---
  // PUT ปกติ
  router.put('/:ownerId/approvals/:approvalId/approve', approveHandler);

  // POST alias: /api/owner/approvals/:approvalId/approve  (หรือ /owner/approvals/...)
  router.post(
    '/approvals/:approvalId/approve',
    // middleware หา ownerId จาก approval
    async (req, res, next) => {
      try {
        const ap = await db.tx(t => getOwnerRowByApproval(t, req.params.approvalId));
        if (!ap) return res.status(404).json({ error: 'NOT_FOUND' });
        req.params.ownerId = String(ap.OwnerID); // ใส่ ownerId ให้ handler ใช้
        return next();
      } catch (e) {
        console.error('POST approve alias error', e);
        return res.status(500).json({ error: 'DB_ERROR' });
      }
    },
    // reuse handler ตัวเดิม
    approveHandler
  );

  // ========== REJECT ==========
  // PUT /api/owner/:ownerId/approvals/:approvalId/reject
  router.put('/:ownerId/approvals/:approvalId/reject', async (req, res) => {
    const t = uniqueTimerLabel('approvals.reject');
    console.time(t);
    res.on('finish', () => console.timeEnd(t));

    const { ownerId, approvalId } = req.params;
    const { reason } = req.body || {};
    try {
      const result = await db.tx(async tx => {
        // ตรวจสิทธิ์ + ล็อกแถว approval
        const ap = await tx.oneOrNone(`
          SELECT TA."ApprovalID", TA."Status"
          FROM public."TenantApproval" TA
          JOIN public."Room"     R ON R."RoomNumber" = TA."RoomNumber"
          JOIN public."Building" B ON B."BuildingID" = R."BuildingID"
          WHERE B."OwnerID"=$1 AND TA."ApprovalID"=$2
          FOR UPDATE
        `, [ownerId, approvalId]);
        if (!ap) return { http: 404, error: 'NOT_FOUND_OR_FORBIDDEN' };
        if (ap.Status !== 'pending') return { http: 409, error: `ALREADY_${ap.Status.toUpperCase()}` };

        const row = await tx.oneOrNone(`
          UPDATE public."TenantApproval"
          SET "Status"='rejected', "Reason"=$3,
              "ApprovedAt"=NOW(), "ApprovedBy"=$1
          WHERE "ApprovalID"=$2
          RETURNING "ApprovalID","Status","Reason","ApprovedAt","ApprovedBy"
        `, [ownerId, approvalId, reason ?? null]);

        return { ok: true, data: row };
      });

      if (result.http) return res.status(result.http).json({ error: result.error });
      res.json(result.data);
    } catch (e) {
      console.error('PUT reject error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // (optional) POST alias สำหรับ reject แบบ legacy
  router.post('/approvals/:approvalId/reject', async (req, res) => {
    try {
      const ap = await db.tx(async t => await getOwnerRowByApproval(t, req.params.approvalId));
      if (!ap) return res.status(404).json({ error: 'NOT_FOUND' });
      req.params.ownerId = String(ap.OwnerID);
      req.params.approvalId = String(ap.ApprovalID);
      // reuse put handler โดยเรียกผ่านฟังก์ชัน
      return router.handle(
        Object.assign(req, { method: 'PUT', url: `/${req.params.ownerId}/approvals/${req.params.approvalId}/reject` }),
        res
      );
    } catch (e) {
      console.error('POST reject alias error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  return router;
};
