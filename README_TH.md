# AMBERLINGS Online — โปรเจกต์ใหม่แยก GitHub / Supabase

> **สถานะ:** แพ็กเกจเตรียมขึ้นออนไลน์ที่สร้างจาก `Amberlings.html` ของคุณ; **ยังไม่ได้สร้าง GitHub Repository หรือ Supabase Project ใหม่** และยังไม่ได้ทดสอบกับฐานข้อมูลจริง เพราะต้องยืนยันองค์กร/ราคาและสร้าง Repository ใหม่ก่อน
>
> โปรเจกต์นี้ **ไม่แตะ** 55 AMBERLANDS, AMBER WORLD CLASS, หรือ Supabase เดิมใด ๆ

## ทำอะไรแล้ว

- คงเกมดั้งเดิมทั้งเอนจิน 3D, ตัวละคร, เมือง, 8 แผนที่, มอนสเตอร์ต้นฉบับ 25 ชนิด, เมนู, เอฟเฟกต์ และระบบเกมออฟไลน์
- เชื่อมปุ่ม Google ไปยัง **Supabase Auth / Google OAuth จริง** ผ่านไลบรารีเวอร์ชันตรึง `@supabase/supabase-js@2.57.0`; ไม่มีการสร้างบัญชี Google จำลอง
- แยกข้อมูลผู้เล่น ตัวละคร มอนสเตอร์ กระเป๋า ตลาด และการพบมอนป่าไว้ในตาราง Supabase ใหม่ `amber_*` (รวม 8 ตาราง โดย 2 ตารางเป็นแคตตาล็อก)
- เปิด RLS ทุกตาราง และ **ไม่อนุญาตให้ `anon` / `authenticated` แก้เงิน ไอเทม มอนสเตอร์ หรือตลาดโดยตรง**; Edge Function ตรวจ JWT และเรียก RPC ผ่าน Service Role ในเซิร์ฟเวอร์เท่านั้น
- มี RPC เซิร์ฟเวอร์สำหรับสร้างตัวละคร, แจกมอนเริ่มต้น, รางวัลรายวัน, ร้านค้าเหรียญ, จัดทีม, รักษาด้วยยา, วิวัฒนาการ, เริ่มพบมอนป่า/โจมตี/จับ, ตั้งขาย/ซื้อ/ยกเลิกมอนในตลาดแบบ Escrow ในธุรกรรมเดียว
- โหมดผู้เยี่ยมชมยังเล่นเกมออฟไลน์ต้นฉบับได้; Google Online ทำงานแยกจากเซฟออฟไลน์ ไม่มีการคัดลอกค่าจากมือถือไปเซิร์ฟเวอร์
- เนื้อหาออนไลน์ที่ยังไม่ได้ย้ายสูตรเซิร์ฟเวอร์ เช่น NPC battle, เควสต์รางวัล, เงินเติม/เจม, กาชา, VIP, คอสตูม และบอตเพื่อน **ถูกปิดในบัญชี Google** ป้องกันการอ้างว่าออนไลน์และสร้างของได้จาก JavaScript

## สถานะที่ยังไม่เสร็จ

- **ยังไม่ใช่ MMO เต็มรูปแบบ**: PvP, ระบบแชทระหว่างผู้เล่นจริง, Realtime Presence, ตลาดไอเทม/แฟชั่น, ระบบจ่ายเงินจริง, เรดบอส และดันเจียนไม่มีระบบครบถ้วน
- สูตรการต่อสู้กับเทรนเนอร์เดิมยังคำนวณในเบราว์เซอร์ จึง **ปิดผลต่อทรัพย์สินออนไลน์**; การต่อสู้จับมอนป่าฝั่งเซิร์ฟเวอร์ใช้เมนู CBT ที่ยังไม่ใช่อนิเมชัน 3D เต็มรูปแบบ
- SQL และ Edge Function ผ่านการตรวจระดับไฟล์ แต่ **ยังไม่ผ่านการรันจริงบน Supabase Project ใหม่** จนกว่าจะสร้าง Project และติดตั้ง
- Google OAuth **ใช้ไม่ได้ทันที** จนกว่าจะตั้งค่า Google Client ID/Secret และ Redirect URLs ใน Supabase Auth
- ต้องทดสอบจริงสองบัญชีหลังติดตั้ง (Google Sign-in → สร้างตัวละคร → รับมอนเริ่มต้น → ซื้อยา → ตั้งขายและซื้อในตลาด)

## โครงสร้างไฟล์

```
public/index.html                        เกม Amberlings ของคุณ + ตัวเชื่อม
public/online-bridge.js                  Google OAuth / adapter แปลงสถานะและคำสั่งออนไลน์
public/online-config.js                  ตั้งค่าที่เปิดเผยได้ของ Supabase Project ใหม่
supabase/001_schema.sql                  ตาราง, RLS, seed มอน 25 ชนิดและไอเทม
supabase/002_server_actions.sql          Atomic RPC, permissions, anti-cheat
supabase/functions/amberlings-api/index.ts  Edge Function ตรวจ JWT
source/Amberlings-original.html           ไฟล์ดั้งเดิมสำรอง (ไม่เผยแพร่ผ่าน Pages)
tests/                                   Smoke tests
.github/workflows/pages.yml               GitHub Pages deploy
```

## ขั้นตอนตั้งค่า (Android / Chrome ก็ทำได้)

1. **GitHub:** เปิด https://github.com/new สร้าง Repository ใหม่ชื่อ `amberlings-online` ภายใต้บัญชีของคุณ (**แยกจาก** `55amberlands.github.io` และ `amber-world-class`) อย่าลบของเดิม
2. อัปโหลดไฟล์ **ข้างใน ZIP** เข้าสู่ Repository ใหม่นี้ (โฟลเดอร์ `.github`, `public`, `source`, `supabase`, `tests` และ README) และเปิด `Settings → Pages → Source: GitHub Actions`
3. **Supabase:** สร้าง Project ใหม่ชื่อ `amberlings-online` ในองค์กรที่คุณเลือก ตรวจค่าใช้จ่ายที่ Supabase เสนอให้ก่อนยืนยัน; เลือก Region Singapore (`ap-southeast-1`)
4. ใน **SQL Editor ของ Project ใหม่เท่านั้น** รัน `supabase/001_schema.sql` แล้วรัน `supabase/002_server_actions.sql` ตรวจว่ามี 25 มอนและคำสั่ง server; ห้ามนำไปรันในเกมเก่า
5. Deploy Edge Function จาก `supabase/functions/amberlings-api/index.ts` ชื่อ `amberlings-api` โดยตั้ง `verify_jwt=true` และเพิ่ม Secret `AMBERLINGS_ALLOWED_ORIGIN=https://YOUR_GITHUB_USERNAME.github.io` (ไม่ต้องใส่ path)
6. เปิด Supabase **Project Settings → API Keys** เอา **Project URL และ publishable key เท่านั้น** ไปใส่ `public/online-config.js`. **ห้าม** ใส่ Secret Key / Service Role ลง GitHub หรือ HTML
7. ตั้งค่า Google Auth ใน [Google Auth Platform](https://console.cloud.google.com/auth/overview): สร้าง OAuth Client ประเภท **Web Application**, authorized origin `https://YOUR_GITHUB_USERNAME.github.io`, authorized redirect URI `https://<NEW_SUPABASE_REF>.supabase.co/auth/v1/callback`
8. เปิด Supabase → Authentication → Providers → Google แล้วใส่ Client ID / Secret **ใน Dashboard เท่านั้น** เปิด Google Provider และตั้ง Authentication → URL Configuration: Site URL + Redirect URL เป็น `https://YOUR_GITHUB_USERNAME.github.io/amberlings-online/`
9. เปิด `https://YOUR_GITHUB_USERNAME.github.io/amberlings-online/` และทดสอบ Google ด้วยสองบัญชีจริง ตรวจข้อมูล SQL, ความคงทนหลังรีโหลด และการแลกเปลี่ยน

Supabase Docs: [Sign in with Google](https://supabase.com/docs/guides/auth/social-sign-in/auth-google), [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls).

## ตรวจสอบความปลอดภัยก่อนเปิดจริง

- ฐานข้อมูลทุกตารางถูกบังคับ RLS และผู้เล่นไม่สามารถ `INSERT/UPDATE/DELETE` แถวเกมผ่าน Data API
- ผู้เล่นผ่าน Edge Function เท่านั้น; Edge Function ใช้ `auth.getUser(jwt)` ยืนยันตัวตนก่อนเรียก RPC
- ฟังก์ชัน RPC เฉพาะ `service_role` และรับ `user_id` จาก JWT ที่ตรวจแล้วเท่านั้น
- เงินและมอนสเตอร์ไม่ได้มาจาก `cloudSave`/`localStorage` — ส่งได้เฉพาะข้อมูลภาพตัวละครในแผนที่ ไม่อนุญาตแนบ balances/creatures/items
- ตลาดใช้ row lock และ transaction เดียวทั้งมอน/เงิน ป้องกันซื้อซ้ำ; ขายมอนต้องเป็นมอนของบัญชีตัวเองเท่านั้น
- ตรวจสอบจริงหลัง deploy ด้วย 2 user accounts และตรวจว่าคำขอปลอมถูกปฏิเสธ ก่อนเปิด Public Beta

**หมายเหตุ:** ไม่ควรเริ่มเปิดเงินจริงหรือเชิญผู้เล่นจำนวนมากก่อนทำ load test และทดสอบฐานข้อมูลจริง
