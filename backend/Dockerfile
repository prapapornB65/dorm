# ใช้ Node base image
FROM node:18

# สร้างโฟลเดอร์ทำงานใน container
WORKDIR /app

# คัดลอกไฟล์ที่ใช้ติดตั้ง
COPY package*.json ./

# ติดตั้ง dependencies
RUN npm install

# คัดลอกโค้ดทั้งหมดเข้า container
COPY . .

# เปิด port
EXPOSE 3000

# รันเซิร์ฟเวอร์
CMD ["node", "server.js"]
