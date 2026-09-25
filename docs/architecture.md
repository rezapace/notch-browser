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
width  = min(1180, screen.frame.width × 0.84)
height = min(800,
             screen.visibleFrame.height × 0.84 + topRail,
             screen.frame.maxY - screen.visibleFrame.minY - 16)
topRail = max(screen.safeAreaInsets.top, statusBarThickness) + 2
```

`visibleFrame` membatasi bagian bawah agar tidak menabrak Dock. Origin negatif display sekunder didukung. Layar dengan notch fisik diprioritaskan; jika tidak ada, gunakan layar utama.

Compact menghitung gap kamera dari `auxiliaryTopLeftArea` dan `auxiliaryTopRightArea`. Label ditempatkan di kedua sisi gap, bukan di belakang kamera.

## Siluet dan tepi tipis

`DynamicNotchShape(.top, cornerRadius: 14, shoulderRadius: 8)` menghasilkan path y-down. `WorkspaceGeometry.silhouette` membaliknya ke y-up AppKit. Path yang sama digunakan untuk mask `CAShapeLayer`, hit-test, dan hover.

| Ukuran | Nilai |
| --- | --- |
| Inset browser kiri/kanan | 10 pt: bahu 8 pt + tepi 2 pt |
| Inset bawah | 2 pt |
| Tambahan di bawah camera/menu-bar rail | 2 pt |
| Sudut konten | 12 pt |
| Tab strip | 30 pt |
| Toolbar | 32 pt |
| Total chrome dengan jarak | 68 pt |

Area halaman memenuhi lebar root tanpa gutter tambahan. Panel tidak bisa di-drag menjadi detached window. Shell hitam menyambung dari tepi layar ke seluruh browser; wallpaper tidak digambar ulang.

## Expand dan collapse

- `showCompact(on:)`: tampilkan label pada panel yang sama.
- `present(on:activate:)`: tampilkan root browser yang sudah ada dan resize selama 240 ms.
- `dismiss`: sembunyikan root tanpa melepas parent, resize ke compact selama 200 ms, tampilkan label lagi.
- Collapse tidak memanggil `orderOut`; panel tetap terlihat sebagai notch kecil.
- `transitionID` mencegah completion collapse lama menimpa reopen.
- `isTransitioning` mencegah pembukaan hover di tengah collapse.
- Reduce Motion mengganti ukuran tanpa interpolasi.

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

Satu `WKWebView` dibuat per tab. Observer URL/title/back/forward dimiliki tab, menggunakan weak capture, dan dibersihkan saat tab ditutup. `window.open` menggunakan konfigurasi WebKit yang diberikan untuk tab baru. URL field menggunakan text engine native macOS.

Root minimal berisi tab strip, navigation row, dan halaman. Tidak ada sidebar, bookmark/history UI, autocomplete, favicon fetch, progress bar, atau header tambahan. Batas perilaku data dijelaskan di [penggunaan](usage.md#data-dan-jaringan).

App terpasang mencari resource di `Contents/Resources`, tanpa fallback `.build`; executable SwiftPM memakai `Bundle.module`. Rincian packaging ada di [pengembangan](development.md#resource-portabel), sedangkan invariant geometri, fokus, dan lifecycle diuji melalui [pengujian](testing.md).
