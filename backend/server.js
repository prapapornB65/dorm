const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');
const bodyParser = require('body-parser');

const app = express();
app.use(cors());
app.use(express.json());

require('dotenv').config();

const db = mysql.createConnection({
  host: process.env.DB_HOST,       
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
  database: process.env.DB_NAME
});


db.connect(err => {
  if (err) throw err;
  console.log('✅ Connected to MySQL');
});

app.get('/ping', (req, res) => {
  res.send('pong');
});


app.post('/api/save-slip', (req, res) => {
  const { bank, amount, datetime, filename } = req.body;
  const sql = 'INSERT INTO payment_slips (bank, amount, datetime, filename) VALUES (?, ?, ?, ?)';
  db.query(sql, [bank, amount, datetime, filename], (err, result) => {
    if (err) return res.status(500).json({ error: err });
    res.json({ success: true, id: result.insertId });
  });
});


// ✅ API: ดึงรายละเอียดห้อง (room_detail_page)
app.get('/api/room/:roomId', (req, res) => {
  const roomId = req.params.roomId;
  const sql = `
    SELECT id, room_number, size, price, furniture, image_url
    FROM rooms
    WHERE id = ?
  `;
  db.query(sql, [roomId], (err, result) => {
    if (err) return res.status(500).json({ error: err });
    if (result.length === 0) return res.status(404).json({ error: 'ไม่พบห้องนี้' });
    res.json(result[0]);
  });
});


// ✅ API: ดึงข้อมูลภาพรวมห้อง + ผู้เช่า (room_overview_page)
app.get('/api/room-overview/:roomId', (req, res) => {
  const roomId = req.params.roomId;
  const sql = `
    SELECT r.room_number, t.name AS tenant_name, t.move_in_date, t.avatar_url
    FROM rooms r
    JOIN tenants t ON r.tenant_id = t.id
    WHERE r.id = ?
  `;
  db.query(sql, [roomId], (err, result) => {
    if (err) return res.status(500).json({ error: err });
    if (result.length === 0) return res.status(404).json({ error: 'ไม่พบข้อมูล' });
    res.json(result[0]);
  });
});


// ✅ API (ตัวอย่างเพิ่ม): ดึงห้องทั้งหมด
app.get('/api/rooms', (req, res) => {
  const sql = `
    SELECT r.id, r.room_number, r.price, r.size, t.name AS tenant_name
    FROM rooms r
    LEFT JOIN tenants t ON r.tenant_id = t.id
    ORDER BY r.room_number ASC
  `;
  db.query(sql, (err, result) => {
    if (err) return res.status(500).json({ error: err });
    res.json(result);
  });
});

const PORT = 3001;
app.listen(PORT, () => console.log(`🚀 Server running on port ${PORT}`));
