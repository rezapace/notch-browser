# NotchBrowser

Browser macOS minimal yang menyatu dengan notch. Hover memperbesar **panel yang sama** ke bawah; tidak ada window browser terpisah di tengah layar.

- Hanya tab (+/×), URL, previous, dan next.
- Tepi tipis, konten aman dari kamera, dan posisi selalu menempel ke atas layar.
- Preview tidak mengambil fokus keyboard; klik untuk berinteraksi.
- Tab dan halaman tetap hidup saat panel dikecilkan.

## Download

Unduh **[NotchBrowser.dmg](https://github.com/rezapace/notch-browser/releases/latest/download/NotchBrowser.dmg)** dari [GitHub Releases](https://github.com/rezapace/notch-browser/releases). Binary tersedia untuk **Apple Silicon (arm64), macOS 13+**. Seret app ke Applications; signing masih ad-hoc dan belum notarized. Panduan instalasi ada di [penggunaan](docs/usage.md#instalasi).

## Mulai cepat

Memerlukan **macOS 13+**, **Swift 5.9+**, dan Apple Command Line Tools. Jalankan dari root folder `notch-browser`:

```sh
git clone https://github.com/rezapace/notch-browser.git
cd notch-browser
./scripts/build.sh
open dist/NotchBrowser.app
```

Untuk installer DMG:

```sh
./scripts/dmg.sh
open dist/NotchBrowser.dmg
```

Tutup versi lama dengan **⌘Q** sebelum menjalankan build baru. Seret aplikasi dari DMG ke **Applications**. Build mengikuti arsitektur Mac yang dipakai; signing masih ad-hoc, **belum notarized**.

## Penggunaan singkat

Hover notch → klik browser → masukkan URL. **⌘L** fokus URL, **⌘T / ⌘W** tambah/tutup tab, **⇧⌘W** kembali ke notch, **⌘Q** keluar.

## Dokumentasi

| Panduan | Isi |
| --- | --- |
| [Penggunaan](docs/usage.md) | Instalasi, hover, shortcut, privasi, dan batasan |
| [Pengembangan](docs/development.md) | Setup, build app/DMG, resource, dan struktur folder |
| [Arsitektur](docs/architecture.md) | Kepemilikan object, satu panel, geometri, dan lifecycle |
| [Pengujian](docs/testing.md) | Tes otomatis, checklist manual, dan validasi distribusi |
| [Lisensi komponen](licenses/THIRD_PARTY_NOTICES.md) | Asal kode/aset dan catatan redistribusi |

## Struktur proyek

```text
notch-browser/
├── README.md
├── Package.swift
├── Sources/NotchBrowser/    # App, Browser, Notch, Resources, Vendor
├── Tests/                  # tes Swift tanpa XCTest
├── Assets/                 # aset untuk packaging
├── scripts/                # build.sh, test.sh, dmg.sh
├── docs/                   # dokumentasi per topik
├── licenses/               # notice dan lisensi upstream
└── dist/                   # hasil app dan DMG; tidak masuk version control
```

Cache SwiftPM berada di `.build/` dan juga diabaikan oleh version control. Pengujian lengkap:

```sh
./scripts/test.sh --bundle
```

**Catatan:** tab belum dipulihkan setelah quit, halaman tersembunyi belum disuspend, dan perilaku perangkat/fullscreen perlu uji manual. Lihat [batasan](docs/usage.md#batasan).
