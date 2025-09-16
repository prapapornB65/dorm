// routes/building.js
const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // ---------- helpers ----------
  function normalizeUrl(raw, base) {
    if (!raw) return null;
    try {
      // ถ้าเป็น absolute และใช้ localhost อยู่ -> แทนที่ด้วย base
      if (/^https?:\/\//i.test(raw)) {
        return raw.replace('http://localhost:3000', base).replace('https://localhost:3000', base);
      }
      // ถ้าเป็น path relative -> join กับ base
      return new URL(raw, base).href;
    } catch (_) {
      // ถ้าแปลงไม่ได้ ก็คืนค่าดิบไปก่อน (อย่างน้อยไม่พัง)
      return raw;
    }
  }

  // ---------- GET /api/buildings[?ownerId=] ----------
  router.get('/buildings', async (req, res) => {
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

      // base สำหรับแก้ URL
      const base = process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`;

      const data = rows.map((r) => ({
        ...r,
        qrCodeUrl: normalizeUrl(r.qrCodeUrl, base), // ✅ คีย์ camelCase + แก้ host
      }));

      res.json({ data });
    } catch (error) {
      console.error('Error fetching buildings:', error);
      res
        .status(500)
        .json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูล', details: error.message });
    }
  });

  // ---------- PUT /api/building/:id ----------
  router.put('/building/:id', async (req, res) => {
    try {
      const buildingId = req.params.id;
      const { BuildingName, Address, Floors, Rooms, OwnerID, Facilities } = req.body;

      if (!BuildingName || !Address || !OwnerID) {
        return res.status(400).json({ error: 'ข้อมูลไม่ครบถ้วน' });
      }

      await db.none(
        `
        UPDATE "Building" SET 
          "BuildingName"=$1,"Address"=$2,"Floors"=$3,"Rooms"=$4,"OwnerID"=$5
        WHERE "BuildingID"=$6
        `,
        [BuildingName, Address, Floors, Rooms, OwnerID, buildingId]
      );

      // reset facilities
      await db.none(`DELETE FROM "BuildingFacility" WHERE "BuildingID"=$1`, [
        buildingId,
      ]);

      if (Facilities && Array.isArray(Facilities) && Facilities.length > 0) {
        const facilityRows = await db.any(
          `SELECT "FacilityID" FROM "Facility" WHERE "FacilityName" = ANY($1)`,
          [Facilities]
        );
        for (const f of facilityRows) {
          await db.none(
            `INSERT INTO "BuildingFacility" ("BuildingID","FacilityID") VALUES ($1,$2)`,
            [buildingId, f.FacilityID]
          );
        }
      }

      res.json({ message: 'แก้ไขตึกสำเร็จ' });
    } catch (error) {
      console.error('Error updating building:', error);
      res
        .status(500)
        .json({ error: 'เกิดข้อผิดพลาดในการแก้ไขตึก', details: error.message });
    }
  });

  // ---------- POST /api/building ----------
  router.post('/building', async (req, res) => {
    try {
      const { BuildingName, Address, Floors, Rooms, OwnerID, Facilities } = req.body;
      if (!BuildingName || !Address || !OwnerID) {
        return res.status(400).json({ error: 'ข้อมูลไม่ครบถ้วน' });
      }

      const result = await db.one(
        `
        INSERT INTO "Building" ("BuildingName","Address","Floors","Rooms","OwnerID")
        VALUES ($1,$2,$3,$4,$5) RETURNING "BuildingID"
        `,
        [BuildingName, Address, Floors, Rooms, OwnerID]
      );
      const buildingId = result.BuildingID;

      if (Facilities && Array.isArray(Facilities) && Facilities.length > 0) {
        const facilityRows = await db.any(
          `SELECT "FacilityID","FacilityName" FROM "Facility" WHERE "FacilityName" = ANY($1)`,
          [Facilities]
        );
        for (const f of facilityRows) {
          await db.none(
            `INSERT INTO "BuildingFacility" ("BuildingID","FacilityID") VALUES ($1,$2)`,
            [buildingId, f.FacilityID]
          );
        }
      }

      res.json({ message: 'เพิ่มตึกสำเร็จ', buildingId });
    } catch (error) {
      console.error('Error adding building:', error);
      res
        .status(500)
        .json({ error: 'เกิดข้อผิดพลาดในการเพิ่มตึก', details: error.message });
    }
  });

  // ---------- GET /api/facilities ----------
  router.get('/facilities', async (_req, res) => {
    try {
      const facilities = await db.any(`SELECT * FROM "Facility"`);
    res.json(facilities);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // ---------- GET /api/building/:id/facilities ----------
  router.get('/building/:id/facilities', async (req, res) => {
    const { id } = req.params;
    try {
      const facilities = await db.any(
        `
        SELECT f."FacilityName"
        FROM "BuildingFacility" bf
        JOIN "Facility" f ON f."FacilityID" = bf."FacilityID"
        WHERE bf."BuildingID" = $1
        `,
        [id]
      );
      res.json(facilities.map((f) => f.FacilityName));
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // ---------- DELETE /api/building/:id ----------
  router.delete('/building/:id', async (req, res) => {
    const buildingId = req.params.id;
    try {
      await db.none(`DELETE FROM "BuildingFacility" WHERE "BuildingID"=$1`, [buildingId]);
      await db.none(`DELETE FROM "Building" WHERE "BuildingID"=$1`, [buildingId]);
      res.json({ message: 'ลบตึกสำเร็จ' });
    } catch (error) {
      console.error('Error deleting building:', error);
      res
        .status(500)
        .json({ error: 'เกิดข้อผิดพลาดในการลบตึก', details: error.message });
    }
  });

  return router;
};
