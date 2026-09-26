# Panduan pengembangan

[README](../README.md) · [Penggunaan](usage.md) · [Arsitektur](architecture.md) · [Pengujian](testing.md)

## Persyaratan

- macOS 13+ dan Swift 5.9+.
- Apple Command Line Tools: `xcode-select --install` jika belum tersedia.
- Sesi desktop macOS untuk tes window, bukan runner headless.
- Tidak memerlukan Xcode GUI, npm, atau library yang diunduh dari jaringan.

Semua perintah berikut dijalankan dari root `notch-browser`. Script juga dapat dipanggil menggunakan absolute path dari direktori mana pun; setiap script menentukan root proyek dari lokasinya sendiri.

## Build aplikasi

Dari root folder proyek, jalankan:

```sh
./scripts/build.sh
open dist/NotchBrowser.app
```

[build.sh](../scripts/build.sh) adalah script zsh (`#!/bin/zsh`) yang melakukan langkah berikut:

1. Mengaktifkan mode gagal-cepat (`set -euo pipefail`), berpindah ke root proyek, dan memastikan host adalah macOS.
2. Mengompilasi executable release melalui SwiftPM dengan optimasi ukuran (`swift build -c release -Xswiftc -Osize`).
3. Membuat ulang `dist/NotchBrowser.app`, lalu menyalin executable, bundle resource, dan notice lisensi ke dalam app bundle.
4. Mengubah `Assets/AppIcon.png` menjadi ikon `.icns` menggunakan `sips` dan `iconutil`.
5. Menulis `Contents/Info.plist` dengan metadata aplikasi, versi, bundle identifier, dan minimum macOS 13.
6. Menghapus simbol debug, memeriksa kebocoran path build, melakukan ad-hoc code signing, dan memverifikasi signature.
7. Menjalankan `--check-resources` untuk memastikan resource dalam app tersedia, lalu mencetak lokasi dan ukuran hasil.

Output selalu **`dist/NotchBrowser.app`**. Build baru menggantikan app hasil build sebelumnya, bukan aplikasi yang terpasang di `/Applications`. Versi app dan deployment minimum untuk bundle berada dalam Info.plist yang ditulis script; versi minimum target juga ada di [Package.swift](../Package.swift).

Build mengikuti arsitektur host. Jangan menyebut hasilnya universal binary tanpa membangun dan memeriksa kedua arsitektur. Signing ad-hoc bukan Developer ID signing dan tidak menyertakan notarization.

## Build DMG

```sh
./scripts/dmg.sh
open dist/NotchBrowser.dmg
```

[dmg.sh](../scripts/dmg.sh) membangun ulang app lalu membuat image HFS+ terkompresi UDZO berisi:

- `NotchBrowser.app`;
- symlink `Applications` menuju `/Applications`;
- `INSTALL.txt` berisi panduan singkat.

Script memverifikasi checksum image, me-mount secara read-only, memverifikasi signature dan resource app dari volume tersebut, lalu eject. DMG baru dipindahkan ke **`dist/NotchBrowser.dmg`** setelah verifikasi berhasil. SHA-256 dan ukuran byte dicetak di terminal; `dist/SHA256SUMS` selalu dibuat ulang agar cocok dengan DMG baru.

DMG tidak menambahkan notarization. Baca [notice komponen](../licenses/THIRD_PARTY_NOTICES.md), khususnya kelengkapan notice Quantum, sebelum redistribusi publik.

## Menjalankan langsung dan diagnostik

```sh
swift run NotchBrowser
swift run NotchBrowser --show
./dist/NotchBrowser.app/Contents/MacOS/NotchBrowser --check-resources
```

- `--show`: mulai expanded dan ambil fokus. Pada app bundle gunakan `open dist/NotchBrowser.app --args --show` setelah keluar dari proses lama.
- `--check-resources`: periksa SVG, cetak lokasi resource, lalu keluar tanpa membuat UI. Exit 1 jika resource hilang/tidak valid.

## Struktur folder

| Lokasi | Tanggung jawab |
| --- | --- |
| `Sources/NotchBrowser/App/` | Entry point dan pencarian resource |
| `Sources/NotchBrowser/Browser/` | UI minimal, tab, navigasi WebKit |
| `Sources/NotchBrowser/Notch/` | Coordinator, panel, geometri, animasi, hover |
| `Sources/NotchBrowser/Resources/` | Resource runtime yang diproses SwiftPM |
| `Sources/NotchBrowser/Vendor/` | Source DynamicNotch yang diadaptasi; jangan campur dengan kode produk |
| `Tests/NotchBrowserTests/` | Test runner Swift mandiri |
| `Assets/` | Aset build-only, seperti sumber ikon aplikasi |
| `scripts/` | Build app, build DMG, dan pengujian |
| `docs/` | Panduan berdasarkan topik |
| `licenses/` | Lisensi dan atribusi komponen |
| `dist/` | Artefak distribusi hasil generate |
| `.build/` | Cache/output sementara SwiftPM |

SwiftPM menemukan file `.swift` secara rekursif dalam target. Resource `Resources/icon.svg` diproses sebagai `icon.svg` dalam `NotchBrowser_NotchBrowser.bundle`; nama bundle dan layout resource runtime tetap sama setelah reorganisasi folder.

## Resource portabel

App bundle menyimpan resource di:

```text
NotchBrowser.app/Contents/Resources/NotchBrowser_NotchBrowser.bundle/icon.svg
```

`AppResources` mencari lokasi ini secara eksplisit untuk `.app`, tanpa fallback ke path `.build` mesin pengembang. Executable bare/`swift run` mencari bundle relatif di sebelah executable. Jangan memakai `Bundle.module`: accessor SwiftPM menyimpan path absolut mesin pembuat sebagai string yang dapat ikut terbawa ke binary release, walaupun `.build/` sudah diabaikan Git. Ikon app `.icns` dan notice lisensi ikut masuk `Contents/Resources`.

Script build mencetak tiga ukuran berbeda: executable bytes, total byte file bundle, dan pemakaian disk. Nilainya bukan penggunaan RAM atau ukuran engine WebKit.

## Pengujian dan cache

```sh
./scripts/test.sh
./scripts/test.sh --bundle
./scripts/perf.sh
```

`perf.sh` menjalankan probe halaman kosong untuk CPU/footprint proses utama dan biaya pembaruan UI. Bukan benchmark JavaScript atau RAM total browser; baca [performa](performance.md).

Rincian coverage dan checklist tersedia di [pengujian](testing.md). Gunakan `swift package clean` untuk membersihkan cache build jika diperlukan; perintah ini tidak menghapus artefak `dist/`. `.build/`, `.swiftpm/`, `dist/`, `.DS_Store`, dan log diabaikan oleh version control.

## Migrasi dari struktur lama

- `./build.sh`, `./test.sh`, `./dmg.sh` → `./scripts/build.sh`, `./scripts/test.sh`, `./scripts/dmg.sh`.
- `NotchBrowser.app` dan `NotchBrowser.dmg` di root → `dist/`.
- `DESIGN.md` → [architecture.md](architecture.md).
- Notice dan lisensi di root → `licenses/`.

Script wrapper lama tidak ditinggalkan agar hanya ada satu lokasi perintah yang perlu dirawat. Tidak ada perubahan bundle identifier, preferensi pengguna, atau perilaku aplikasi akibat reorganisasi ini.
