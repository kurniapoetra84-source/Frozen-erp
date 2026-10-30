# Frozen ERP — Starter v0.1

Aplikasi awal ERP distribusi frozen food berbasis React + Vite + Supabase, siap di-host pada Cloudflare Pages dan disimpan di GitHub.

## Status fitur pada starter ini

Sudah disiapkan:
- Login/registrasi Supabase Auth.
- Dashboard ringkas: jumlah produk, stok, pesanan bulan ini, dan batch mendekati expired.
- Master produk, pelanggan, supplier, biaya operasional.
- Tampilan data stok batch, PO, dan sales order.
- Form tambah data sederhana untuk master dan transaksi header.
- Skema PostgreSQL untuk PO/receiving, sales order/DO, invoice, pembayaran parsial, utang/piutang, expenses, stock movements.
- RPC alokasi stok FEFO dan trigger saldo pembayaran invoice/tagihan.
- PWA manifest dan layout responsif.

Belum selesai pada starter ini (tahap pengembangan berikutnya):
- Form detail item PO/SO, penerimaan batch dan DO yang memanggil RPC FEFO.
- Alur transaksi penuh yang atomik dari PO sampai stok dan SO sampai invoice.
- Pengaturan nomor dokumen otomatis, approval, pembatasan izin per modul yang lebih rinci.
- Export PDF/Excel/CSV, audit log, backup otomatis dan notifikasi expired.
- Pengujian end-to-end dan hardening keamanan sebelum dipakai untuk operasional produksi.

**Penting:** jangan gunakan sebagai satu-satunya sistem pembukuan/stock produksi sebelum modul transaksi lengkap dan pengujian selesai.

## 1. Buat project Supabase

1. Buat project baru di https://supabase.com/dashboard.
2. Buka **SQL Editor → New query**.
3. Salin seluruh isi `supabase/schema.sql`, lalu jalankan.
4. Daftar akun pertama melalui aplikasi (atau Supabase Auth).
5. Di SQL Editor, jalankan perintah bootstrap Owner berikut. Ganti nama jika perlu:

```sql
update public.profiles
set role = 'owner', full_name = 'Owner'
where id = (select id from auth.users order by created_at asc limit 1);
```

6. Ambil **Project URL** dan **anon/public key** dari Project Settings → API. Jangan pernah menaruh `service_role` key di browser atau GitHub.

## 2. Jalankan lokal

Perlu Node.js 20 atau versi LTS terbaru.

```bash
npm install
cp .env.example .env
```

Isi `.env`:

```env
VITE_SUPABASE_URL=https://PROJECT_ID.supabase.co
VITE_SUPABASE_ANON_KEY=SUPABASE_ANON_PUBLIC_KEY
```

Lalu:

```bash
npm run dev
```

Untuk memeriksa build:

```bash
npm run build
```

## 3. Upload ke GitHub

1. Buat repository baru bernama `frozen-erp`.
2. Upload seluruh isi folder project ini (bukan file ZIP-nya saja), atau push dengan Git.
3. Pastikan `.env` tidak ikut di-upload. `.gitignore` sudah mengecualikannya.

## 4. Deploy Cloudflare Pages

1. Buka https://dash.cloudflare.com/ → Workers & Pages → Create → Pages → Connect to Git.
2. Pilih repository `frozen-erp`.
3. Build command: `npm run build`
4. Build output directory: `dist`
5. Tambahkan environment variables pada Pages → Settings → Environment variables:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
6. Deploy. Setelah deploy, buka URL `*.pages.dev`.

## 5. Role pengguna

Role tersedia: `owner`, `admin`, `sales`, `warehouse`, `delivery`, `finance`.
Akun baru otomatis mendapat role `sales`. Owner/admin dapat mengubah role melalui SQL untuk tahap awal:

```sql
update public.profiles set role='warehouse'
where id=(select id from auth.users where email='gudang@perusahaan.com');
```

## Catatan keamanan & operasional

- `anon/public` key memang digunakan di frontend; keamanan data bergantung pada Row Level Security (RLS).
- Jangan pernah memasukkan `service_role` key ke `.env` frontend.
- Schema ini adalah fondasi pengembangan. Kebijakan tulis saat ini masih memberi akses operasional luas kepada semua role staff dan perlu diperketat berdasarkan tugas sebelum dipakai tim.
- Supabase Free dapat memiliki batas kuota, jeda project yang tidak aktif, dan fitur backup terbatas. Simpan backup database secara berkala.
- Cloudflare Pages cocok untuk hosting frontend statis; database dan autentikasi tetap di Supabase.
