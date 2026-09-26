# Pengujian dan validasi

[README](../README.md) · [Penggunaan](usage.md) · [Pengembangan](development.md) · [Arsitektur](architecture.md)

## Menjalankan tes

Dari root `notch-browser`:

```sh
./scripts/test.sh
./scripts/test.sh --bundle
```

[test.sh](../scripts/test.sh) mengompilasi [WorkspaceTests.swift](../Tests/NotchBrowserTests/WorkspaceTests.swift) dengan source browser/notch yang dibutuhkan, menjalankannya, lalu membersihkan executable sementara. Tes tidak memakai XCTest agar kompatibel dengan Command Line Tools yang tidak menyertakan framework tersebut. Gunakan script ini, bukan `swift test`.

Tes window memerlukan sesi desktop macOS dan akan menampilkan panel sementara. Jangan mengubah fokus aplikasi selama tes fokus berjalan karena dapat mengubah hasilnya. Tidak memerlukan internet. Tes loading menjalankan fixture HTTP sementara yang hanya bind ke loopback `127.0.0.1` dengan port dinamis; request tidak dicatat.

## Coverage otomatis

| Kelompok | Yang diperiksa |
| --- | --- |
| Geometri layar | Top anchor, viewport target, layar kecil, origin negatif, dan Dock kiri/kanan |
| Border dan kamera | Inset tipis, rail kamera, sudut konten di dalam siluet |
| Kebijakan interaksi | Preview, key focus, dan sheet mengendalikan auto-close |
| Panel tunggal | Compact memakai satu nonactivating panel; identitas panel/shell/browser tetap |
| Animasi | Top anchor tetap selama resize; completion lama tidak menimpa reopen |
| Lifecycle | Expand/collapse berulang tidak melepas browser dari parent |
| Fokus | Preview tidak merebut frontmost application atau key focus |
| Mask/hit-test | Siluet sama; repeated layout memakai ulang path mask |
| Chrome minimal | Hanya tab strip, navigation row, dan halaman; toolbar dua tombol dan satu URL field |
| Layout konten | Overlay 68 pt tidak mengubah ukuran halaman; tidak ada mask halaman bertingkat |
| Tab | 20 tab kosong berbagi satu engine cadangan; adopsi saat navigasi, tutup tab terakhir, dan cleanup WebView |
| Popup | WebView langsung dibuat; konfigurasi/store yang diberikan WebKit tidak diganti |
| WebKit | Store persisten bersama, dark appearance, popup otomatis diblokir, inspector release mati |
| Auto-hide | Hover/editor/fokus/sheet/home/pin menahan hide; dirty title ditunda lalu diterapkan pada reveal |
| Input | Memilih tab aktif tidak mengubah fokus; metadata tidak menimpa teks URL yang sedang diedit |
| Timing | Navigasi HTTP lokal benar-benar selesai di URL fixture; field numerik saja, callback lama/tab tertutup diabaikan |

`--bundle` menambahkan build release, pemeriksaan path build di binary, dan tiga pengujian resource:

1. Salinan app di lokasi sementara harus membaca resource dari dalam app itu sendiri.
2. Executable bare yang dipindah harus membaca resource bundle di sebelahnya.
3. Setelah resource salinan app dihapus, validasi harus gagal walaupun `.build` pengembang masih tersedia.

Tes negatif hanya mengubah salinan sementara, bukan artefak di `dist/`. Build juga memverifikasi signature dan resource.

## Validasi DMG

```sh
./scripts/dmg.sh
```

Script memverifikasi checksum image, me-mount read-only, memeriksa signature dan resource app, memastikan shortcut Applications benar, lalu eject. Hasil akhir ada di `dist/NotchBrowser.dmg` dan checksum baru di `dist/SHA256SUMS`.

Build/verifikasi yang berhasil tidak berarti app sudah notarized. Panduan instalasi aman tersedia di [penggunaan](usage.md#instalasi).

## Checklist manual sebelum distribusi

- [ ] Hover notch fisik membuka preview tanpa mencuri fokus.
- [ ] Pointer dapat bergerak ke bawah tanpa celah; collapse/reopen tidak berkedip.
- [ ] Klik pertama, URL field, IME, copy/paste, dan shortcut bekerja.
- [ ] Kontrol auto-hide setelah keluar area atas, reveal hover tidak berkedip, ⌘L tetap aman saat IME.
- [ ] WebView tidak resize saat reveal/hide; bagian halaman di bawah overlay dapat diakses setelah hide.
- [ ] Dark-mode situs yang mendukungnya, sudut bawah 28 pt, VoiceOver, dan menu pin diuji visual.
- [ ] Previous/next, tab baru, tab terakhir, dan `window.open` bekerja pada situs nyata.
- [ ] Navigasi sangat cepat setelah startup (sebelum warm-up selesai), redirect, reload setelah gagal, dan rapid tab-close tidak menerima callback navigasi lama.
- [ ] Bandingkan first load/repeat load dengan diagnostik opt-in, kemudian matikan flag untuk benchmark resmi.
- [ ] Halaman gagal dimuat dapat dicoba lagi dengan ⌘R.
- [ ] ⇧⌘W kembali ke notch; ⌘Q tidak meninggalkan panel.
- [ ] Reduce Motion bekerja tanpa animasi resize.
- [ ] Kamera tidak menutupi kontrol; menu bar dan Dock tetap dapat digunakan.
- [ ] Monitor eksternal dilepas/dipasang, Spaces, dan fullscreen diuji.
- [ ] Dialog/sheet website tidak menyebabkan auto-close yang salah.
- [ ] App yang disalin dari DMG berjalan dari Applications, termasuk resource-nya.

Kelulusan tes otomatis **bukan** klaim semua interaksi atau tampilan perangkat sudah tervalidasi. Screenshot visual belum menjadi bagian test runner.

## Pengukuran performa

Jalankan `./scripts/perf.sh` untuk probe UI/tab kosong dan first/repeat load fixture HTTP loopback. Hitungan WebView termasuk satu cadangan yang belum dimiliki tab. `isLoading == false` adalah akhir pengukuran fixture, bukan first paint. Constructor UI yang cepat tidak berarti pemanasan WebKit dihapus; pekerjaan tersebut ditunda ke main queue. Prosedur perbandingan website dan batas angka pengukuran dijelaskan di [performa](performance.md).

## Laporan masalah

Sertakan versi macOS, arsitektur (`uname -m`), jumlah/konfigurasi monitor, versi aplikasi, langkah reproduksi, perilaku yang diharapkan, serta output build/test terkait. Hindari membagikan URL privat, cookie, atau data login.
