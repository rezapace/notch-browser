# Performa dan cache

[README](../README.md) · [Arsitektur](architecture.md) · [Pengujian](testing.md)

## Optimisasi v0.7.1

- Dirty flag dipisah menjadi **title, address, history**. KVO judul hanya memperbarui label tab/judul window; tidak lagi memproses address bar atau tombol navigasi. Perubahan URL tetap menandai title karena host dipakai sebagai fallback untuk judul kosong.
- Flag tetap dikumpulkan saat chrome tersembunyi. Penyelesaian editing dan Escape meminta sinkronisasi URL terbaru tanpa menimpa teks yang sedang diketik.
- `didFinish` tab background/tertutup tidak lagi mengulang timer auto-hide toolbar aktif. Toolbar yang sudah tersembunyi atau dipin tidak membuat work item hide baru.
- Counter kategori refresh hanya dikompilasi dengan `BROWSER_TESTING` pada test runner; tidak masuk binary release. Tes mengamati KVO nyata dari JavaScript fixture, bukan hanya fungsi dirty flag.
- Mask notch, tracking pointer, konfigurasi WebKit, forced layout, dan lifecycle halaman dipertahankan. Belum ada bukti profiling untuk mengubah bagian tersebut dengan aman.

### Pengukuran wrapper v0.7.0 → v0.7.1

Tiga run per versi, bergantian v0.7.0 lalu v0.7.1, pada Mac16,12 / 16 GiB / macOS 15.7.4 dengan `scripts/perf.sh` dan `-Osize`. Baseline source dari tag v0.7.0; tidak ada counter test yang aktif. Tabel menunjukkan **median antar-run**, bukan skor website:

| Pengukuran | v0.7.0 | v0.7.1 |
| --- | ---: | ---: |
| Constructor browser | 3,81 ms | 3,82 ms |
| Median presentasi 10 tab per run | 0,013 ms | 0,012 ms |
| Footprint proses utama, 10 tab kosong | 18,50 MiB | 18,47 MiB |
| First load HTTP loopback setelah idle | 30,93 ms | 34,44 ms |
| Repeat load HTTP loopback | 8,73 ms | 8,48 ms |

First load berkisar 28,94–35,60 ms pada baseline dan 31,05–38,16 ms pada patch. Median first load justru naik pada sampel ini; tiga run tidak cukup untuk memastikan regresi atau perbaikan kecil. Patch tidak mengklaim mempercepat loading. Pengukuran berakhir saat `isLoading == false`, bukan first paint. CPU/footprint hanya proses utama, bukan WebContent/GPU/network.

Hasil yang dibuktikan tes adalah **penghapusan jalur refresh yang tidak relevan** dan isolasi timer tab aktif. Probe tab kosong di atas terutama menjaga karakteristik startup/lifecycle; tidak menstimulasi beban metadata yang dioptimalkan. Tidak ada klaim peningkatan Speedometer atau menutup gap terhadap Chrome.

## Optimisasi v0.7.0

- Constructor browser hanya menyiapkan UI native. Satu work item sesudahnya memanaskan **satu WebView cadangan** dengan HTML lokal, bukan website. Cadangan dipakai oleh tab normal pertama yang bernavigasi; tab kosong lain tidak membuat engine sendiri.
- Lazy penuh tanpa cadangan sempat diuji, tetapi memperlambat navigasi pertama karena engine masih dingin. Karena itu pendekatan tersebut **tidak dipakai sebagai default**.
- Saat chrome auto-hide, KVO hanya menandai dirty state. Reveal menerapkan metadata terakhir sekali. Model halaman tetap hidup; URL yang sedang diketik tidak ditimpa.
- Memilih tab aktif menjadi no-op. Struktur tab hanya dilayout ketika diperlukan; nilai UI identik tidak diset ulang.
- Pemilihan pool eksplisit dihapus: SDK WebKit menyatakan `WKProcessPool` tidak lagi berpengaruh sejak macOS 12. Store persisten dan konfigurasi asli popup tetap dipertahankan.
- Flag diagnostik [loading opt-in](development.md#diagnostik-loading-opt-in) tersedia untuk membedakan fase jaringan/navigasi tanpa merekam URL atau data halaman. Bukan flag akselerasi.

### Pengukuran pembanding

Satu run per konfigurasi pada Mac16,12 / 16 GiB / macOS 15.7.4, Swift 6.2.4, `-Osize`. Source baseline diambil dari tag v0.6.0 dan memakai workload probe yang sama:

| Pengukuran | v0.6.0 | v0.7.0 |
| --- | ---: | ---: |
| Constructor `BrowserController` | 28,33 ms | 3,91 ms |
| Median `prepareForPresentation`, 10 tab | 0,015 ms | 0,005 ms |
| WebView untuk 10 tab kosong, termasuk cadangan | 10 | 1 |
| Footprint proses utama, 10 tab kosong | 19,06 MiB | 18,74 MiB |
| First load fixture HTTP setelah idle | 23,85 ms | 26,49 ms |
| Repeat load fixture, WebView sama | 7,22 ms | 7,90 ms |

Constructor tidak lagi membayar pemanasan engine secara sinkron; **pekerjaan pemanasan tetap ada sesudahnya**, bukan hilang. Pengukuran first load berakhir saat `WKWebView.isLoading == false`, bukan first paint. Selisih loading kecil pada satu run tidak membuktikan percepatan/regresi website; perlu beberapa run terkontrol. Varian lazy penuh tanpa cadangan mencatat first load 98,54 ms pada fixture yang sama sehingga ditolak.

Tujuan patch adalah mengurangi pekerjaan UI dan alokasi tab kosong tanpa penalti cold load sebesar varian lazy penuh. Tidak ada klaim peningkatan skor Speedometer. Jumlah WebView bukan jumlah proses WebKit dan footprint di atas bukan RAM total browser.

## Optimisasi v0.6.0

- View tab/tombol dipakai ulang. KVO URL/title/back/forward digabung per runloop, hanya label yang berubah diperbarui; pembaruan ketika compact ditunda.
- Mask/frame dicache berdasarkan input geometri. Resize nyata tetap memperbarui mask agar rendering dan hit-test konsisten.
- Satu mask shell mempertahankan notch dan sudut bawah 28 pt; mask tambahan pada halaman dihapus. Dampak GPU belum diukur dengan Instruments, sehingga bukan klaim peningkatan FPS tertentu.
- Tab/URL auto-hide sebagai overlay. Viewport WebKit tidak berubah ketika kontrol muncul/hilang maupun saat panel expand/collapse.
- Ukuran halaman menargetkan 850×650 atau lebih jika layar memungkinkan, dengan batas window 1180×900 dan ruang aman Dock. Layar kecil tetap dibatasi agar panel tidak keluar layar.
- Konfigurasi normal memakai store persisten dan pool bersama. Config `window.open` yang diberikan WebKit tidak ditimpa. Inspector hanya aktif di build debug.

## GPU, CPU, dan disk cache

WKWebView menggunakan optimisasi engine WebKit sistem, termasuk JIT dan GPU compositing jika tersedia. Tidak ada saklar publik untuk memaksa “full GPU/CPU”. Pemilihan process pool bukan saklar akselerasi; pada macOS yang didukung aplikasi, WebKit mengatur prosesnya sendiri. Tab tidak berbagi heap JavaScript hanya karena memakai store yang sama.

`WKWebsiteDataStore.default()` mempertahankan profil lama, cookie, HTTP cache, localStorage, dan IndexedDB. Tidak ada store UUID baru, penghapusan otomatis, prefetch, atau cache `URLCache` buatan untuk halaman WebKit. Server tetap menentukan cacheability response; WebKit mengelola kapasitas dan eviction. Kuota storage situs berbeda dari ukuran HTTP cache.

Tab tersembunyi tidak dihentikan atau dikosongkan otomatis: `stopLoading()` bukan suspend JavaScript dan unload dapat menghilangkan formulir, audio, atau sesi. Untuk tes berat, gunakan satu tab. Suspend halaman yang sudah dimuat dan session restore belum diimplementasikan. Lazy allocation untuk tab kosong kini digunakan dengan satu engine cadangan.

## Probe lokal yang dapat diulang

```sh
./scripts/perf.sh
```

Probe memakai build `-Osize`, halaman kosong, 80 iterasi `prepareForPresentation()`, sampel CPU idle empat detik, dan 20 siklus expand/collapse. Probe baru juga menghitung alokasi WebView dan first/repeat load fixture HTTP loopback. Ia tidak menjalankan seluruh startup app/coordinator dan tidak mengukur FPS atau Speedometer.

Contoh satu pengukuran lokal Apple Silicon / RAM 16 GB / macOS 15.7.4:

| Median pembaruan UI | v0.5.0 | v0.6.0 |
| --- | ---: | ---: |
| 1 tab | 0,660 ms | 0,030 ms |
| 5 tab | 1,977 ms | 0,016 ms |
| 10 tab | 4,156 ms | 0,033 ms |

Footprint proses utama pada 10 tab kosong: 22,08 → 17,78 MiB. CPU idle proses utama pada sampel v0.6.0 berkisar 0,015–0,147%. Angka ini **tidak mencakup subprocess WebKit, GPU, atau networking**, bukan RAM total browser, dan sampel singkat bukan pengujian energi jangka panjang. Variasi kecil antarjumlah tab adalah noise; jangan menafsirkan tabel sebagai performa website.

## Probe pembanding engine dan shell

[engine-baseline.sh](../scripts/engine-baseline.sh) mengompilasi executable pengembang sementara, bukan mengganti aplikasi terpasang:

```sh
./scripts/engine-baseline.sh plain
./scripts/engine-baseline.sh notch
```

Kedua mode memakai `WebKitRuntime.configuration()`, appearance gelap, dan ukuran viewport yang dihitung dari geometri layar NotchBrowser. `plain` memakai satu WKWebView dalam window biasa opaque tanpa mask/toolbar. `notch` memakai shell dan BrowserController produksi, tetapi tanpa coordinator hover/collapse; panel sengaja tetap terbuka. Perbedaannya mencakup beberapa komponen shell sekaligus, **bukan isolasi biaya mask saja**.

Default membuka Speedometer **3.1** secara interaktif. Anda menjalankan dan menyimpan hasilnya sendiri. Untuk membandingkan versi lain, berikan **URL yang sama persis** di kedua mode, misalnya `./scripts/engine-baseline.sh plain https://browserbench.org/Speedometer3.0/`. Jangan mencampur versi benchmark saat membandingkan hasil lama.

Tidak ada injeksi script atau deteksi khusus Speedometer, pengubahan GPU/JIT flags, pengumpulan skor otomatis, maupun logging URL/konten. Probe memakai kebijakan store persisten; jangan menganggap cache/profil executable pengembang identik dengan app terpasang atau Safari. Samakan kondisi warm-up/cache secara eksplisit. Probe bukan browser lengkap dan tidak mengukur subprocess otomatis.

Smoke test kedua mode hanya mengakses fixture loopback dan memeriksa URL fixture, viewport, serta kebijakan datastore:

```sh
./scripts/engine-baseline.sh plain --smoke-test
./scripts/engine-baseline.sh notch --smoke-test
```

Jika WKWebView minimal sebanding dengan NotchBrowser, selidiki engine/versi sebelum mengubah shell. Jika ada gap berulang, lanjutkan Instruments pada proses utama/WebContent dan jalur rendering. Bandingkan juga Safari dan Chrome; Safari bukan embedding WKWebView yang identik. Belum ada hasil Speedometer baru dari probe ini yang membuktikan percepatan.

## Mengukur website secara adil

1. Gunakan Safari dan NotchBrowser pada mesin/versi macOS yang sama, satu tab, workload dan viewport yang sebanding.
2. Tunggu animasi selesai; pastikan halaman terlihat dan kontrol sudah tersembunyi. Catat `innerWidth`/`innerHeight` melalui Inspector build debug jika diperlukan.
3. Catat kondisi cache, Low Power Mode, sumber daya listrik, dan thermal. Beri jeda antar-run; laporkan median minimal tiga run.
4. Jangan menyuntik script/content blocker yang mengubah workload benchmark. Jangan menyimpulkan semua error harness disebabkan viewport.

Belum ada perbandingan Speedometer terkontrol atau pengukuran GPU frame-time yang membuktikan peningkatan dari patch terbaru. Optimisasi wrapper tidak mengubah engine WebKit menjadi engine Safari versi berbeda.
