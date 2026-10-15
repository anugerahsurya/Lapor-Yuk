# Render ulang video promosi

Butuh ffmpeg (mis. dari paket `imageio-ffmpeg`) dan Python dengan numpy.
Semua perintah dijalankan dari root proyek.

1. Gambar (900 frame, 1080x1920, tanpa suara):

   ```bash
   FFMPEG=/path/ffmpeg OUT=promo_silent.mp4 flutter test tool/promo/promo_video_test.dart
   ```

   Cek frame tertentu dulu sebagai PNG: `PREVIEW="4.5,10,26" OUT=<folder> flutter test tool/promo/promo_video_test.dart`

2. Musik dan efek suara: `python tool/promo/audio.py promo_audio.wav`

3. Gabung. Versi Instagram Story (1080x1920) dan versi aplikasi (720x1280):

   ```bash
   ffmpeg -i promo_silent.mp4 -i promo_audio.wav -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart release/LaporYuk_Promo_1080x1920.mp4
   ffmpeg -i promo_silent.mp4 -i promo_audio.wav -vf scale=720:1280:flags=lanczos -c:v libx264 -preset slow -crf 24 -pix_fmt yuv420p -c:a aac -b:a 128k -shortest -movflags +faststart assets/video/promo.mp4
   ```

Waktu adegan ada di `starts` (promo_video_test.dart) dan efek suara di bagian
`sfx` (audio.py); kalau satu digeser, geser juga yang lain.
