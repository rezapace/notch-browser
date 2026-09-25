# Panduan penggunaan

[README](../README.md) · [Pengembangan](development.md) · [Arsitektur](architecture.md) · [Pengujian](testing.md)

## Instalasi

1. Buka `dist/NotchBrowser.dmg` hasil build.
2. Jika versi lama berjalan, keluar dengan **⌘Q**.
3. Seret `NotchBrowser.app` ke shortcut **Applications**.
4. Eject DMG, lalu jalankan aplikasi dari Applications.

Aplikasi memerlukan macOS 13+. Build lokal mengikuti arsitektur mesin pembuatnya, bukan universal binary. Pengujian lokal dilakukan pada Apple Silicon.

Signing masih **ad-hoc**, belum Developer ID/notarized. Jika macOS memblokir aplikasi, gunakan **System Settings → Privacy & Security → Open Anyway** hanya jika Anda mempercayai sumbernya. Tidak perlu menonaktifkan Gatekeeper secara global.

## Hover dan fokus

1. Startup menampilkan compact notch. Layar dengan notch fisik diprioritaskan; tanpa notch fisik digunakan top-center layar utama.
2. Hover selama **120 ms** memperbesar panel menjadi preview tanpa mengambil fokus keyboard aplikasi lain.
3. Gerakkan pointer langsung ke bawah menuju browser. Klik untuk mulai mengetik atau menggunakan halaman.
4. Sebelum diklik, keluar dari preview selama **350 ms** mengecilkan panel kembali.
5. Setelah browser mendapat key focus, pointer keluar saja tidak menutupnya. Pindah fokus ke aplikasi lain menyebabkan collapse setelah 350 ms, kecuali ada sheet terpasang.
6. **⇧⌘W** mengecilkan panel; tombol **× pada tab** hanya menutup tab tersebut.
7. Jika pointer masih di compact notch setelah manual collapse, keluar dan masuk kembali untuk memicu hover berikutnya. Klik compact tetap dapat membuka langsung.

Klik ikon Dock untuk membuka browser secara eksplisit. Panel tidak dapat di-drag atau dilepas dari notch. Tidak ada tombol tutup workspace tambahan.

## Kontrol dan pintasan

UI hanya berisi tab horizontal (+/×), kolom URL, previous, dan next. Tab panjang dapat di-scroll horizontal; halaman awal sengaja kosong.

| Pintasan | Fungsi |
| --- | --- |
| ⌘L | Fokus address bar |
| ⌘T / ⌘W | Tambah / tutup tab |
| ⌘1 … ⌘9 | Pilih tab |
| ⌘[ / ⌘] | Previous / next |
| ⌘R | Reload, tanpa tombol toolbar |
| Escape di address bar | Batalkan edit URL dan kembali ke halaman |
| ⇧⌘W | Collapse ke notch |
| ⌘Q | Keluar dari aplikasi |

## Data dan jaringan

- WebKit mengelola persistent website store, cookie, dan HTTP cache.
- Tidak ada request autocomplete atau favicon tambahan. Input URL diproses saat Enter; teks biasa membuka Google Search setelah Enter.
- Halaman website yang sudah terbuka tetap dapat membuat request sendiri.
- History/bookmark UI dan preferensi sidebar lama tidak lagi dipakai. Data/cache lama tidak dihapus otomatis.
- Collapse tidak menghancurkan tab atau WebView. Login website mengikuti penyimpanan WebKit.

## Batasan

- Tab belum dipulihkan setelah quit/relaunch.
- Halaman tersembunyi masih dapat menjalankan JavaScript/audio; belum ada suspend otomatis.
- Preview tidak menangkap keyboard sebelum diklik. Pembukaan aplikasi lewat Finder/macOS sendiri dapat mengaktifkan aplikasinya.
- Desktop dan window lain di belakang browser tetap terlihat; aplikasi tidak mengganti wallpaper atau memaksa semua aplikasi lain tersembunyi.
- Reduce Motion menonaktifkan interpolasi ukuran. Interaksi notch fisik, IME, dialog, Spaces/fullscreen, dan monitor eksternal tetap perlu pengujian perangkat.

## Jika tampilan belum berubah setelah update

Keluar dengan **⌘Q**, pastikan aplikasi yang dibuka adalah salinan baru di Applications atau `dist/`, lalu jalankan ulang. Menjalankan `open` ketika proses lama masih hidup dapat membuka instance lama tersebut.

Untuk masalah build/resource, lihat [pengembangan](development.md). Untuk laporan bug, sertakan versi macOS, arsitektur, konfigurasi monitor, dan langkah reproduksi seperti dijelaskan di [pengujian](testing.md).
