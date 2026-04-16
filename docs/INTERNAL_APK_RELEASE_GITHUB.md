# Internal APK Release via GitHub

## 1) Siapkan signing release

Salin template lalu isi dengan data keystore lokal:

```bash
cp android/key.properties.example android/key.properties
```

`android/key.properties`:

- `storeFile` harus path absolut ke file `.jks`/`.keystore`
- file ini jangan di-commit

## 2) Build APK release

```bash
flutter build apk --release
```

Output:

- `build/app/outputs/flutter-apk/app-release.apk`

## 3) Upload ke GitHub Releases

1. Buat tag baru, contoh: `v1.0.1`
2. Buat release dari tag tersebut
3. Upload file APK dengan nama **`app-release.apk`**

Penting:

- Nama file harus tetap `app-release.apk` agar URL latest tetap stabil.

URL latest yang dipakai QR:

`https://github.com/GospelSugarvi/vtrack-vivo/releases/latest/download/app-release.apk`

## 4) Cek QR di aplikasi

Buka menu profil -> Tentang aplikasi -> scan QR.
Pastikan membuka URL latest GitHub di atas.

## 5) Update berikutnya

1. Naikkan versi di `pubspec.yaml`
2. Build ulang `flutter build apk --release`
3. Upload APK baru ke release terbaru (nama file tetap `app-release.apk`)
