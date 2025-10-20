// routes/building.js
const express = require('express');

module.exports = (db, requireAuthOptional, requireOwnerOptional) => {
  const router = express.Router();

  // ---------- auth middlewares (optional) ----------
  const requireAuth = requireAuthOptional || ((_req, _res, next) => next());
  const requireOwner = requireOwnerOptional || ((_req, _res, next) => next());

  // ---------- helpers ----------
  function normalizeUrl(raw, base) {
    if (!raw) return null;
    try {
      if (/^https?:\/\//i.test(raw)) {
        return raw
          .replace('http://localhost:3000', base)
          .replace('https://localhost:3000', base);
      }
      return new URL(raw, base).href;
    } catch (_) {
      return raw;
    }
  }

  function toIntOrNull(v) {
    if (v === undefined || v === null || v === '') return null;
    const n = Number(v);
    return Number.isFinite(n) ? Math.trunc(n) : null;
  }

  function baseUrlFrom(req) {
    return process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`;
  }

  function rowToCamel(r, base) {
    return {
      buildingId: r.buildingId,
      buildingName: r.buildingName,
      address: r.address,
      floors: r.floors,
      rooms: r.rooms,
      ownerId: r.ownerId,
      qrCodeUrl: normalizeUrl(r.qrCodeUrl, base),
    };
  }

  // ---------- GET /api/buildings[?ownerId=] ----------
  router.get('/buildings', requireAuth, requireOwner, async (req, res) => {
    try {
      const ownerId = req.query.ownerId ? Number(req.query.ownerId) : null;

      const rows = await db.any(
        `
        SELECT 
          "BuildingID"   AS "buildingId",
          "BuildingName" AS "buildingName",
          "Address"      AS "address",
          "Floors"       AS "floors",
          "Rooms"        AS "rooms",
          "OwnerID"      AS "ownerId",
          "QrCodeUrl"    AS "qrCodeUrl"
        FROM public."Building"
        ${ownerId ? 'WHERE "OwnerID" = $1' : ''}
        ORDER BY "BuildingID" ASC
        `,
        ownerId ? [ownerId] : []
      );

      const base = baseUrlFrom(req);
      res.json({ data: rows.map(r => rowToCamel(r, base)) });
    } catch (error) {
      console.error('Error fetching buildings:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูล', details: error.message });
    }
  });

  // ---------- GET /api/building/:id ----------
  router.get('/building/:id', requireAuth, requireOwner, async (req, res) => {
    try {
      const id = Number(req.params.id);
      if (!Number.isInteger(id)) {
        return res.status(400).json({ error: 'building id ไม่ถูกต้อง' });
      }

      const r = await db.oneOrNone(
        `
        SELECT 
          "BuildingID"   AS "buildingId",
          "BuildingName" AS "buildingName",
          "Address"      AS "address",
          "Floors"       AS "floors",
          "Rooms"        AS "rooms",
          "OwnerID"      AS "ownerId",
          "QrCodeUrl"    AS "qrCodeUrl"
        FROM public."Building"
        WHERE "BuildingID" = $1
        `,
        [id]
      );

      if (!r) return res.status(404).json({ error: 'ไม่พบบ้าน/ตึกนี้' });

      const base = baseUrlFrom(req);
      res.json(rowToCamel(r, base));
    } catch (error) {
      console.error('Error fetching building:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูล', details: error.message });
    }
  });

  // ---------- PUT /api/building/:id ----------
  router.put('/building/:id', requireAuth, requireOwner, async (req, res) => {
    const buildingId = Number(req.params.id);
    const {
      BuildingName, Address, Floors, Rooms, OwnerID, Facilities, QrUrl
    } = req.body || {};

    const floors = toIntOrNull(Floors);
    const rooms = toIntOrNull(Rooms);

    if (!BuildingName || !Address || !OwnerID) {
      return res.status(400).json({ error: 'ข้อมูลไม่ครบถ้วน' });
    }
    if (floors !== null && floors < 0) return res.status(400).json({ error: 'จำนวนชั้นต้องไม่ติดลบ' });
    if (rooms !== null && rooms < 0) return res.status(400).json({ error: 'จำนวนห้องต้องไม่ติดลบ' });

    const tx = isTx(db) ? db : db.tx ? db : null;

    try {
      if (tx && db.tx) {
        await db.tx(async t => {
          await updateBuilding(t, buildingId, BuildingName, Address, floors, rooms, OwnerID, QrUrl);
          await resetFacilities(t, buildingId, Facilities);
        });
      } else {
        await updateBuilding(db, buildingId, BuildingName, Address, floors, rooms, OwnerID, QrUrl);
        await resetFacilities(db, buildingId, Facilities);
      }

      res.json({ message: 'แก้ไขตึกสำเร็จ' });
    } catch (error) {
      console.error('Error updating building:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการแก้ไขตึก', details: error.message });
    }
  });

  // ---------- POST /api/building ----------
  router.post('/building', requireAuth, requireOwner, async (req, res) => {
    try {
      const { BuildingName, Address, Floors, Rooms, OwnerID, Facilities } = req.body || {};

      const floors = toIntOrNull(Floors);
      const rooms = toIntOrNull(Rooms);

      if (!BuildingName || !Address || !OwnerID) {
        return res.status(400).json({ error: 'ข้อมูลไม่ครบถ้วน' });
      }
      if (floors !== null && floors < 0) return res.status(400).json({ error: 'จำนวนชั้นต้องไม่ติดลบ' });
      if (rooms !== null && rooms < 0) return res.status(400).json({ error: 'จำนวนห้องต้องไม่ติดลบ' });

      const inserted = await db.one(
        `
        INSERT INTO "Building" ("BuildingName","Address","Floors","Rooms","OwnerID")
        VALUES ($1,$2,$3,$4,$5) RETURNING "BuildingID"
        `,
        [BuildingName, Address, floors, rooms, OwnerID]
      );

      const buildingId = inserted.BuildingID;

      if (Facilities && Array.isArray(Facilities) && Facilities.length > 0) {
        await db.tx(async t => {
          await setFacilities(t, buildingId, Facilities);
        });
      }

      res.json({ message: 'เพิ่มตึกสำเร็จ', buildingId });
    } catch (error) {
      console.error('Error adding building:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการเพิ่มตึก', details: error.message });
    }
  });

  // ---------- GET /api/facilities ----------
  router.get('/facilities', requireAuth, requireOwner, async (_req, res) => {
    try {
      const facilities = await db.any(`SELECT "FacilityID","FacilityName" FROM "Facility" ORDER BY "FacilityName" ASC`);
      res.json(facilities);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // ---------- GET /api/building/:id/facilities ----------
  router.get('/building/:id/facilities', requireAuth, requireOwner, async (req, res) => {
    const { id } = req.params;
    try {
      const facilities = await db.any(
        `
        SELECT f."FacilityName"
        FROM "BuildingFacility" bf
        JOIN "Facility" f ON f."FacilityID" = bf."FacilityID"
        WHERE bf."BuildingID" = $1
        ORDER BY f."FacilityName" ASC
        `,
        [id]
      );
      res.json(facilities.map((f) => f.FacilityName));
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // ---------- DELETE /api/building/:id ----------
  router.delete('/building/:id', requireAuth, requireOwner, async (req, res) => {
    const buildingId = Number(req.params.id);
    if (!Number.isInteger(buildingId)) {
      return res.status(400).json({ error: 'building id ไม่ถูกต้อง' });
    }
    try {
      await db.tx(async t => {
        await t.none(`DELETE FROM "BuildingFacility" WHERE "BuildingID"=$1`, [buildingId]);
        await t.none(`DELETE FROM "Building" WHERE "BuildingID"=$1`, [buildingId]);
      });
      res.json({ message: 'ลบตึกสำเร็จ' });
    } catch (error) {
      console.error('Error deleting building:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการลบตึก', details: error.message });
    }
  });

  // ---------- local helpers for queries ----------
  function isTx(dbOrTx) {
    return typeof dbOrTx.none === 'function' && typeof dbOrTx.any === 'function' && !!dbOrTx.ctx;
  }

  async function updateBuilding(conn, id, name, address, floors, rooms, ownerId, qrUrl) {
    await conn.none(
      `
      UPDATE "Building" SET
        "BuildingName"=$1,
        "Address"=$2,
        "Floors"=$3,
        "Rooms"=$4,
        "OwnerID"=$5,
        "QrCodeUrl"=$6
      WHERE "BuildingID"=$7
      `,
      [name, address, floors, rooms, ownerId, qrUrl || null, id]
    );
  }

  async function resetFacilities(conn, buildingId, facilities) {
    await conn.none(`DELETE FROM "BuildingFacility" WHERE "BuildingID"=$1`, [buildingId]);
    if (facilities && Array.isArray(facilities) && facilities.length > 0) {
      await setFacilities(conn, buildingId, facilities);
    }
  }

  async function setFacilities(conn, buildingId, facilities) {
    const rows = await conn.any(
      `SELECT "FacilityID","FacilityName" FROM "Facility" WHERE "FacilityName" = ANY($1)`,
      [facilities]
    );
    for (const f of rows) {
      await conn.none(
        `INSERT INTO "BuildingFacility" ("BuildingID","FacilityID") VALUES ($1,$2)`,
        [buildingId, f.FacilityID]
      );
    }
  }

  return router;
};
