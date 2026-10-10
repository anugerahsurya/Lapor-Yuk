# Lapor Yuk

Aplikasi Android (Flutter) untuk mencatat kegiatan harian dan menyiapkan laporan kinerja (CKP/SKP) bulanan.
Bekerja penuh tanpa internet; internet hanya dipakai untuk sinkron Google Drive dan chat.

- Lapor kegiatan: capaian otomatis *"Persentase Terselesaikannya … Sebesar 100%"*, periode tunggal/rentang (maks. 1 bulan ke belakang), kegiatan lintas bulan ditandai **Lanjutan**
- Bukti dukung: kamera 3:4 dengan watermark (nama, waktu, alamat, koordinat, geotag EXIF), galeri, PDF; tersimpan di `Lapor Yuk/YYYY-MM/`
- Rekap PDF bulanan bertanda tangan, To Do, pengingat harian (Sabtu–Minggu libur)
- Sinkron Google Drive ke folder `SKP <nama>` (link: pengomentar) + tombol salin kegiatan / capaian / link bukti untuk SKP
- Chat antar pengguna (Supabase)

## Struktur

| Path | Isi |
|---|---|
| `lib/` | Aplikasi Flutter |
| `android/` | Proyek Android (Kotlin: encoder JPEG + EXIF) |
| `supabase/migrations/` | Skema chat + row-level security |
| `landing/` | Halaman unduh statis (deploy ke Vercel, *Root Directory* = `landing`) |
| `tool/make_icons.py` | Generator ikon aplikasi |

## Build

```bash
cp env.example.json env.json   # isi GOOGLE_WEB_CLIENT_ID & SUPABASE_ANON_KEY
flutter build apk --release --split-per-abi --dart-define-from-file=env.json
```

Tanda tangan rilis dibaca dari `android/key.properties` (tidak ikut repo).

## Lisensi aset

Font Plus Jakarta Sans (OFL). Maskot avatar dari [ipaslogo.com](https://ipaslogo.com) (bebas dipakai, termasuk komersial).
