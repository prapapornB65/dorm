// routes/owner/ownerApprovals.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

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

  // GET /api/owner/:ownerId/approvals?status=&q=&buildingId=&room=&limit=&offset=
  router.get('/:ownerId/approvals', async (req, res) => {
    console.time('approvals.list');
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

      // ✔ pg-promise คืน array ตรง ๆ
      const rows = await db.any(sql, args);
      res.json(rows);
    } catch (e) {
      console.error('GET owner approvals error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // GET /api/owner/:ownerId/approvals/summary
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

  router.put('/:ownerId/approvals/:approvalId/approve', async (req, res) => {
    const { ownerId, approvalId } = req.params;

    try {
      const ok = await db.tx(async t => {
        // 0) ระบุตึกให้ชัด ด้วย RoomNumber + OwnerID
        const roomScope = await t.oneOrNone(`
        WITH room_scope AS (
          SELECT R."RoomNumber", R."BuildingID"
          FROM public."Room" R
          JOIN public."Building" B ON B."BuildingID" = R."BuildingID"
          WHERE B."OwnerID" = $1
            AND R."RoomNumber" = (SELECT "RoomNumber" FROM public."TenantApproval" WHERE "ApprovalID" = $2)
          LIMIT 1
        )
        SELECT * FROM room_scope;
      `, [ownerId, approvalId]);

        if (!roomScope) return false;

        // 1) เปลี่ยนสถานะ + คืน payload
        const ap = await t.oneOrNone(`
        UPDATE public."TenantApproval" TA
        SET "Status"='approved',
            "Reason"=NULL,
            "ApprovedAt"=NOW(),
            "ApprovedBy"=$2
        WHERE TA."ApprovalID"=$1
        RETURNING TA."TenantID", TA."RoomNumber", TA."FullName", TA."Email", TA."Payload";
      `, [approvalId, ownerId]);
        if (!ap) return false;

        const p = ap.Payload || {};
        const [firstName, ...rest] = (ap.FullName || '').trim().split(/\s+/);
        const lastName = rest.join(' ') || null;

        // 2) upsert Tenant (ถ้าไม่ได้ใช้รหัสผ่านฝั่ง backend ให้เก็บเป็น NULL หรือ 'NOT_STORED_IN_DB')
        await t.none(`
        INSERT INTO public."Tenant"
          ("TenantID","FirstName","LastName","CitizenID","BirthDate","Email","Phone","UserName","Password",
           "RoomNumber","Start","End","ProfileImage","Role","FirebaseUID")
        VALUES (
          COALESCE($1,DEFAULT), $2,$3,$4,$5,$6,$7,$8,$9,
          $10, CURRENT_DATE, NULL, NULL, 'tenant', NULL
        )
        ON CONFLICT ("TenantID") DO UPDATE SET
          "FirstName"=EXCLUDED."FirstName",
          "LastName" =EXCLUDED."LastName",
          "CitizenID"=EXCLUDED."CitizenID",
          "BirthDate"=EXCLUDED."BirthDate",
          "Email"    =EXCLUDED."Email",
          "Phone"    =EXCLUDED."Phone",
          "UserName" =EXCLUDED."UserName",
          "Password" =EXCLUDED."Password",
          "RoomNumber"=EXCLUDED."RoomNumber";
      `, [
          ap.TenantID ?? null,
          firstName, lastName,
          p.citizenID ?? null,
          p.birthDate ?? null,
          ap.Email,
          p.phone ?? null,
          p.username ?? null,
          p.passwordHash ?? null, // ถ้าใช้ Firebase อย่างเดียว แนะนำให้ส่งเป็น NULL/NOT_STORED_IN_DB
          ap.RoomNumber
        ]);

        // 3) อัปเดตสถานะห้องแบบเจาะจง BuildingID
        await t.none(`
        UPDATE public."Room"
        SET "Status"='occupied'
        WHERE "RoomNumber"=$1 AND "BuildingID"=$2;
      `, [roomScope.RoomNumber, roomScope.BuildingID]);

        return true;
      });

      if (!ok) return res.status(404).json({ error: 'NOT_FOUND_OR_FORBIDDEN' });
      res.json({ approved: true });
    } catch (e) {
      console.error('PUT approve error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  // PUT /api/owner/:ownerId/approvals/:approvalId/reject
  router.put('/:ownerId/approvals/:approvalId/reject', async (req, res) => {
    const { ownerId, approvalId } = req.params;
    const { reason } = req.body || {};
    try {
      const row = await db.oneOrNone(`
      WITH room_scope AS (
        SELECT R."RoomNumber", R."BuildingID"
        FROM public."Room" R
        JOIN public."Building" B ON B."BuildingID" = R."BuildingID"
        WHERE B."OwnerID" = $2
          AND R."RoomNumber" = (SELECT "RoomNumber" FROM public."TenantApproval" WHERE "ApprovalID" = $1)
        LIMIT 1
      )
      UPDATE public."TenantApproval" TA
      SET "Status"='rejected',
          "Reason"=$3,
          "ApprovedAt"=NOW(),
          "ApprovedBy"=$2
      WHERE TA."ApprovalID"=$1
      RETURNING TA."ApprovalID", TA."TenantID", TA."RoomNumber", TA."FullName",
                TA."Email", TA."Status", TA."Reason", TA."RequestDate",
                TA."ApprovedAt", TA."ApprovedBy";
    `, [approvalId, ownerId, reason ?? null]);

      if (!row) return res.status(404).json({ error: 'NOT_FOUND_OR_FORBIDDEN' });
      res.json(row);
    } catch (e) {
      console.error('PUT reject error', e);
      res.status(500).json({ error: 'DB_ERROR' });
    }
  });

  return router;
};
