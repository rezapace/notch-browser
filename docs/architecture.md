# Arsitektur: satu panel, dua ukuran

[README](../README.md) · [Penggunaan](usage.md) · [Pengembangan](development.md) · [Pengujian](testing.md)

## Prinsip utama

Compact notch dan browser expanded adalah **NSPanel yang sama**, bukan dua window yang bergantian ditampilkan. Panel selalu menempel ke tengah tepi atas layar. Root browser dipasang sekali dan tidak dipindah antar-parent saat animasi.

AppKit mengelola panel dan chrome, WebKit merender website. Source vendored DynamicNotch menyediakan siluet berbasis SwiftUI, tetapi `DynamicNotchWindowController` asal tidak dibuat oleh aplikasi. Tidak ada polling mouse, event monitor global, atau overlay fullscreen.

## Kepemilikan object

```text
AppDelegate
└── NotchCoordinator
    ├── WorkspaceWindow: NSPanel
    │   └── WorkspaceSurface: NSView
    │       ├── label / ikon compact
    │       └── BrowserController.root
    │           ├── tab strip horizontal (+/×)
    │           ├── previous / next / URL
    │           └── WKWebView per tab
    └── BrowserController → panel yang sama
```

| File | Tanggung jawab |
| --- | --- |
| [AppDelegate.swift](../Sources/NotchBrowser/App/AppDelegate.swift) | Startup, Dock reopen, shutdown, flag CLI |
| [AppResources.swift](../Sources/NotchBrowser/App/AppResources.swift) | Resource bundle portabel |
| [BrowserController.swift](../Sources/NotchBrowser/Browser/BrowserController.swift) | Kontrol native, tab, URL, WebKit, menu shortcut |
| [BrowserRootView.swift](../Sources/NotchBrowser/Browser/BrowserRootView.swift) | Tracking reveal area dan kebijakan auto-hide kontrol |
| [WebKitRuntime.swift](../Sources/NotchBrowser/Browser/WebKitRuntime.swift) | Konfigurasi WebKit dan profil cache persisten bersama |
| [NotchCoordinator.swift](../Sources/NotchBrowser/Notch/NotchCoordinator.swift) | Screen selection, hover, debounce, kebijakan fokus |
| [WorkspaceWindow.swift](../Sources/NotchBrowser/Notch/WorkspaceWindow.swift) | Panel, shell, geometry, mask, animasi, tracking |
| [DynamicNotch.swift](../Sources/NotchBrowser/Vendor/DynamicNotch.swift) | Source vendored; `DynamicNotchShape` dipakai shell |

Delegate ditahan dengan `withExtendedLifetime`. Callback lintas object memakai weak capture. Coordinator membatalkan work item dan melepas observer saat shutdown.

## Geometri top-attached

AppKit memakai sumbu Y ke atas. Compact dan expanded menggunakan:

```text
x = screen.frame.midX - width / 2
y = screen.frame.maxY - height
```

`frame.maxY` tetap sama dengan top layar di kedua mode dan selama interpolasi animasi. Jangan mengganti anchor ini dengan `visibleFrame.maxY`, karena area menu bar yang dikecualikan dapat menimbulkan celah di bawah notch.

```text
width  = min(1180, availableWidth,
             max(850 + 20, screen.frame.width × 0.84))
height = min(900, availableHeight,
             max(650 + topRail + 2, screen.visibleFrame.height × 0.90 + topRail))
topRail = max(screen.safeAreaInsets.top, statusBarThickness) + 2
```

`availableHeight` adalah jarak dari top layar ke batas bawah `visibleFrame`, dikurangi 16 pt. `availableWidth` membatasi lebar secara simetris terhadap tengah layar agar Dock kiri/kanan juga dihormati. Target halaman 850×650 hanya dipenuhi jika ruang layar memungkinkan; tidak memaksa window keluar layar. Origin negatif display sekunder didukung. Layar dengan notch fisik diprioritaskan; jika tidak ada, gunakan layar utama.

Compact menghitung gap kamera dari `auxiliaryTopLeftArea` dan `auxiliaryTopRightArea`. Label ditempatkan di kedua sisi gap, bukan di belakang kamera.

## Siluet dan tepi tipis

`DynamicNotchShape(.top, cornerRadius: 28, shoulderRadius: 8)` menghasilkan path y-down saat expanded; compact mempertahankan radius 14. `WorkspaceGeometry.silhouette` membaliknya ke y-up AppKit. Path yang sama digunakan untuk mask `CAShapeLayer`, hit-test, dan hover.

| Ukuran | Nilai |
| --- | --- |
| Inset browser kiri/kanan | 10 pt: bahu 8 pt + tepi 2 pt |
| Inset bawah | 2 pt |
| Tambahan di bawah camera/menu-bar rail | 2 pt |
| Sudut bawah shell expanded | 28 pt; satu mask untuk shell dan halaman |
| Tab strip | 32 pt |
| Toolbar | 36 pt |
| Total overlay chrome | 68 pt |
| Reveal area ketika kontrol tersembunyi | 8 pt |

Area halaman memenuhi seluruh root tanpa gutter tambahan. Tab/toolbar berada di atas halaman sebagai overlay solid gelap, tanpa resize WebKit saat auto-hide. Mask bertingkat di `pages` dihapus; mask shell tetap diperlukan untuk menjaga bentuk notch, sudut bawah, dan hit-test yang sama. Window tetap non-opaque, bukan kotak hitam yang menutupi area transparan sudut. Panel tidak bisa di-drag menjadi detached window. Shell hitam menyambung dari tepi layar ke seluruh browser; wallpaper tidak digambar ulang.

## Expand dan collapse

- `showCompact(on:)`: tampilkan label pada panel yang sama.
- `present(on:activate:)`: tampilkan root browser yang sudah ada dan resize selama 240 ms.
- `dismiss`: sembunyikan root tanpa melepas parent, resize ke compact selama 200 ms, tampilkan label lagi.
- Collapse tidak memanggil `orderOut`; panel tetap terlihat sebagai notch kecil.
- `transitionID` mencegah completion collapse lama menimpa reopen.
- `isTransitioning` mencegah pembukaan hover di tengah collapse.
- Reduce Motion mengganti ukuran tanpa interpolasi.

Geometri dicache berdasarkan bounds, ukuran browser, top rail, gap kamera, dan state expanded. Layout dengan input yang sama tidak membangun path atau mengubah frame WebView lagi. Selama animasi, path tetap diperbarui ketika ukuran benar-benar berubah agar mask dan hit-test tidak tertinggal.

Viewport browser tetap berukuran expanded. Shell mengungkap konten lewat clipping selama resize, bukan memaksa WebKit layout ulang ke lebar compact setiap frame.

## Hover dan fokus

```text
compact --hover 120 ms--> expanded preview
                         ├─ pointer di dalam → tetap tampil
                         ├─ keluar 350 ms → collapse
                         └─ klik → interactive / key window
                                   ├─ masih key → jangan tutup karena pointer keluar
                                   ├─ kehilangan key 350 ms tanpa sheet → collapse
                                   └─ ⇧⌘W → collapse
```

Klik compact, Dock reopen, dan `--show` mengambil fokus secara eksplisit. Jalur hover hanya menampilkan panel tanpa `NSApp.activate`. Panel nonactivating boleh menjadi key hanya ketika expanded, tidak menjadi main window.

Kebijakan auto-close adalah fungsi murni:

```swift
!isKey && !hasSheet && (hasInteracted || !pointerInside)
```

Setelah manual collapse, pointer yang tetap di compact harus keluar dahulu untuk mengaktifkan hover berikutnya. Tidak ada timeout perjalanan antardua window, karena compact dan browser merupakan satu bidang tersambung.

Tracking menggunakan `NSTrackingArea` `.activeAlways` untuk enter/exit/move, termasuk saat app tidak aktif. Delay memakai work item sekali jalan, bukan polling berulang.

## Browser dan resource

Satu `WKWebView` dibuat per tab. Tab normal memakai `WebKitRuntime` dengan `WKWebsiteDataStore.default()` dan pool bersama; ini tidak menjamin satu proses web. Tidak ada reset profil atau UUID store baru. `window.open` menggunakan konfigurasi WebKit yang diberikan **tanpa mengganti pool/store-nya**.

Observer URL/title/back/forward dimiliki tab, menggunakan weak capture, dan dibersihkan saat tab ditutup. Perubahan digabung per runloop dan hanya memperbarui label tab yang kotor; view tombol/tab dipertahankan sampai tab ditutup. Pembaruan KVO ketika compact ditunda sampai presentasi berikutnya. Perubahan judul tidak memindahkan scroll tab. URL field menggunakan text engine native macOS.

Auto-hide memakai timer sekali jalan 800 ms dan tracking enter/exit area atas, bukan polling. ⌘L, tab kosong, editor aktif, fokus kontrol, sheet, dan opsi pin menjaga kontrol dapat diakses. Appearance gelap diteruskan ke WebKit; tidak ada injeksi CSS atau manipulasi engine. Inspector hanya aktif pada build `DEBUG`.

Root minimal berisi tab strip, navigation row, dan halaman. Tidak ada sidebar, bookmark/history UI, autocomplete, favicon fetch, progress bar, atau header tambahan. Batas perilaku data dijelaskan di [penggunaan](usage.md#data-dan-jaringan).

App terpasang mencari resource di `Contents/Resources`, tanpa fallback `.build`; executable SwiftPM mencari bundle di sebelah executable. `Bundle.module` tidak direferensikan karena accessor hasil generate menanam path build absolut. Build distribusi menolak binary yang masih mengandung path home/proyek mesin pembuat. Rincian packaging ada di [pengembangan](development.md#resource-portabel), sedangkan invariant geometri, fokus, dan lifecycle diuji melalui [pengujian](testing.md).
