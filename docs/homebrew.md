# Instalasi Homebrew

[README](../README.md) · [Penggunaan](usage.md) · [Pengembangan](development.md)

## Install

Untuk **Apple Silicon (arm64), macOS 13+**, dengan Homebrew yang sudah terpasang:

```sh
brew install --cask rezapace/notch-browser/notch-browser
```

Homebrew otomatis menambahkan tap [rezapace/homebrew-notch-browser](https://github.com/rezapace/homebrew-notch-browser). Gunakan `--cask` karena ini aplikasi GUI, bukan formula CLI. Tidak perlu mengompilasi Swift atau memasang Xcode untuk menggunakan DMG release.

Alternatif dengan tap eksplisit:

```sh
brew tap rezapace/notch-browser
brew install --cask rezapace/notch-browser/notch-browser
```

Untuk nama pendek pada Homebrew 6+, percayai **cask ini saja**, bukan seluruh tap:

```sh
brew trust --cask rezapace/notch-browser/notch-browser
brew install --cask notch-browser
```

`brew trust` hanya diperlukan untuk aturan trust pada Homebrew baru; perintah fully qualified di atas sudah memberikan trust pada item yang dipasang. Homebrew versi lama belum memiliki perintah `brew trust`.

## Update dan uninstall

Keluar dari aplikasi dengan **⌘Q** sebelum update:

```sh
brew update
brew upgrade --cask rezapace/notch-browser/notch-browser
```

Menghapus aplikasi:

```sh
brew uninstall --cask rezapace/notch-browser/notch-browser
```

Cask tidak memiliki hook `zap` atau skrip penghapus data. Cookie, cache, dan profil WebKit tidak dihapus otomatis. Bila sebelumnya memasang DMG manual, Homebrew mungkin menolak karena `/Applications/NotchBrowser.app` sudah ada: keluar dari aplikasi dan pindahkan **app bundle lama saja** sebelum mencoba kembali. Jangan menghapus folder data browser.

## Keamanan dan batasan

- Cask menunjuk URL versi tetap di GitHub Releases dan SHA-256 DMG tersebut, bukan `latest` atau `sha256 :no_check`.
- Binary belum universal: Mac Intel tidak didukung oleh cask ini.
- Signing masih **ad-hoc**, belum Developer ID/notarized. Homebrew tidak mengubah status tersebut.
- Jika macOS memblokir pembukaan, gunakan **System Settings → Privacy & Security → Open Anyway** hanya bila mempercayai sumbernya. Tidak ada hook untuk menghapus quarantine atau menonaktifkan Gatekeeper.
- Ini tap proyek sendiri, **bukan** paket yang sudah diterima di `Homebrew/homebrew-cask`.

## Memelihara tap

Definisi yang dipasang pengguna berada di repository terpisah:

```text
homebrew-notch-browser/
├── Casks/notch-browser.rb
└── README.md
```

Repository aplikasi menyediakan [scripts/homebrew.sh](../scripts/homebrew.sh) untuk menghasilkan cask dari **DMG final**, bukan dari versi app lokal yang mungkin berbeda:

```sh
./scripts/test.sh --bundle
./scripts/dmg.sh
./scripts/homebrew.sh > dist/notch-browser.rb
```

Generator memverifikasi checksum, mount DMG read-only, membaca versi/minimum macOS/arsitektur dari app dalam DMG, memeriksa signature dan path build, kemudian mencetak Ruby ke stdout. Log validasi masuk stderr. Generator tidak membuat release atau push secara otomatis.

Urutan rilis:

1. Build/test, buat DMG final dan cask. Periksa versi, URL, SHA, dan syarat arsitekturnya.
2. Commit/tag source, upload **DMG yang sama** beserta `SHA256SUMS`, lalu verifikasi hasil download release.
3. Salin `dist/notch-browser.rb` ke `Casks/notch-browser.rb` pada tap. Commit/push perubahan tap hanya setelah URL release tersedia.
4. Jalankan `brew style`, `brew audit --cask --online`, dan uji install ke appdir sementara. Periksa hasil signing audit secara terpisah: build ad-hoc belum memenuhi notarization Apple.

Jangan membangun ulang atau menimpa DMG pada tag yang sudah dipakai cask: hasil image baru dapat memiliki checksum berbeda. Rilis versi baru dan perbarui version/SHA cask bersama-sama.
