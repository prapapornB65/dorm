const express = require('express');

module.exports = (db) => {
  const router = express.Router();

  // GET /api/admin-notifications
  router.get('/admin-notifications', async (_req, res) => {
    try {
      const rows = await db.any(`
        SELECT
          n."NotificationID" AS id,
          n."CreatedAt"      AS created_at,
          n."Title"          AS title,
          n."Message"        AS message,
          n."IsRead"         AS is_read,
          t."FirstName"      AS tenant_first_name,
          t."LastName"       AS tenant_last_name
        FROM public."Notification" n
        LEFT JOIN public."Tenant" t ON n."TenantID" = t."TenantID"
        ORDER BY n."CreatedAt" DESC;
      `);

      const notifications = rows.map(row => ({
        id: String(row.id),
        time: new Date(row.created_at)
          .toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit', hour12: false }) + ' น.',
        date: new Date(row.created_at)
          .toLocaleDateString('th-TH', { year: '2-digit', month: '2-digit', day: '2-digit' }),
        type: row.title || 'ทั่วไป',
        detail: row.message || 'ไม่มีรายละเอียด',
        status: row.is_read ? 'อ่านแล้ว' : 'ยังไม่อ่าน',
        rawDateTime: new Date(row.created_at).toISOString(),
        tenantName: `${row.tenant_first_name || ''} ${row.tenant_last_name || ''}`.trim() || undefined
      }));

      res.json(notifications);
    } catch (error) {
      console.error('❌ Error fetching admin notifications:', error);
      res.status(500).json({ error: 'เกิดข้อผิดพลาดในการดึงข้อมูลการแจ้งเตือน', details: error.message });
    }
  });

  // POST /api/notifications/mark-read/:id
  router.post('/notifications/mark-read/:id', async (req, res) => {
    const notificationId = Number(req.params.id);
    if (!Number.isInteger(notificationId)) {
      return res.status(400).json({ error: 'notificationId ไม่ถูกต้อง' });
    }
    try {
      await db.none(`
        UPDATE public."Notification"
        SET "IsRead" = TRUE
        WHERE "NotificationID" = $1;
      `, [notificationId]);
      res.status(200).json({ message: 'Marked as read' });
    } catch (error) {
      console.error('❌ Error marking notification as read:', error);
      res.status(500).json({ error: 'Failed to mark as read' });
    }
  });

  // DELETE /api/notifications/:id
  router.delete('/notifications/:id', async (req, res) => {
    const notificationId = Number(req.params.id);
    if (!Number.isInteger(notificationId)) {
      return res.status(400).json({ error: 'notificationId ไม่ถูกต้อง' });
    }
    try {
      await db.none(`
        DELETE FROM public."Notification"
        WHERE "NotificationID" = $1;
      `, [notificationId]);
      res.status(200).json({ message: 'Notification deleted' });
    } catch (error) {
      console.error('❌ Error deleting notification:', error);
      res.status(500).json({ error: 'Failed to delete notification' });
    }
  });

  return router;
};
