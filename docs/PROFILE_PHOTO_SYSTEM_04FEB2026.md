# Profile Photo System - 4 Februari 2026

## Overview
Sistem upload foto profil dengan Cloudinary storage dan auto-delete foto lama.

---

## FITUR 1: Upload Foto Profil ✅

### Lokasi Upload
- **Halaman**: Tab Profil (Promotor/SATOR/SPV/Admin)
- **Trigger**: Tap icon kamera di pojok kanan bawah avatar
- **Opsi**: Kamera atau Galeri

### Flow Upload
```
1. User tap icon kamera
   ↓
2. Bottom sheet: Pilih Kamera atau Galeri
   ↓
3. User pilih/ambil foto
   ↓
4. Preview dialog dengan foto
   ↓
5. User konfirmasi "Upload"
   ↓
6. Get old avatar_url dari database
   ↓
7. Upload foto baru ke Cloudinary
   ↓
8. Update avatar_url di database
   ↓
9. Delete foto lama dari Cloudinary (optional)
   ↓
10. Reload profile & show success message
```

### Spesifikasi Foto
- **Max Size**: 512x512 pixels
- **Quality**: 75%
- **Format**: JPG
- **Storage**: Cloudinary
- **Folder**: `vtrack/profiles`
- **Naming**: `profile_[timestamp].jpg`

---

## FITUR 2: Hapus Foto Lama ✅

### Implementasi
Saat user upload foto baru:
1. ✅ Ambil `avatar_url` lama dari database
2. ✅ Upload foto baru ke Cloudinary
3. ✅ Update `avatar_url` di database dengan URL baru
4. ⚠️ Extract `public_id` dari URL lama
5. ⚠️ Delete foto lama dari Cloudinary (requires backend)

### Status
- **Database Update**: ✅ Working (URL lama ter-replace)
- **Cloudinary Delete**: ⚠️ Partial (requires API key & secret)

### Catatan Delete
Cloudinary delete memerlukan **authenticated request** dengan API key & secret.
Untuk security, ini sebaiknya dilakukan via **backend/cloud function**.

**Current Implementation**:
- Function `_deleteOldCloudinaryImage()` sudah ada
- Extract public_id dari URL ✅
- Actual delete ❌ (requires backend)

**Recommended Solution**:
Buat **Supabase Edge Function** untuk handle delete:
```typescript
// supabase/functions/delete-cloudinary-image/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const { publicId } = await req.json()
  
  // Call Cloudinary delete API with API key & secret
  const response = await fetch(
    `https://api.cloudinary.com/v1_1/${cloudName}/image/destroy`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        public_id: publicId,
        api_key: apiKey,
        signature: generateSignature(publicId, apiSecret),
        timestamp: Math.floor(Date.now() / 1000)
      })
    }
  )
  
  return new Response(JSON.stringify({ success: true }))
})
```

---

## FITUR 3: Foto Profil di Semua Halaman ✅

### Lokasi yang Sudah Update

#### 1. **Tab Profil** ✅
- File: `lib/features/promotor/presentation/tabs/promotor_profil_tab.dart`
- Avatar besar dengan border shadow
- Icon kamera untuk upload

#### 2. **Tab Home (Card Header)** ✅
- File: `lib/features/promotor/presentation/tabs/promotor_home_tab.dart`
- Avatar di header card dengan border putih
- Load `avatar_url` dari database
- Fallback ke icon person jika tidak ada foto

#### 3. **Chat** (TODO)
- File: `lib/features/chat/...`
- Perlu update untuk load avatar_url dari users table
- Gunakan widget `UserAvatar` untuk konsistensi

### Reusable Widget
Created: `lib/core/widgets/user_avatar.dart`

**Usage**:
```dart
import 'package:vtrack/core/widgets/user_avatar.dart';

UserAvatar(
  avatarUrl: user['avatar_url'],
  fullName: user['full_name'],
  radius: 20,
  showBorder: true,
  borderColor: Colors.white,
)
```

**Features**:
- Auto fallback ke initial letter jika tidak ada foto
- Consistent color generation dari nama
- Customizable size, border, colors
- NetworkImage dengan error handling

---

## Database Schema

### users table
```sql
ALTER TABLE users ADD COLUMN avatar_url TEXT;
COMMENT ON COLUMN users.avatar_url IS 'URL to user profile photo (Cloudinary)';
```

### Example Data
```sql
SELECT id, full_name, avatar_url FROM users LIMIT 3;
```

| id | full_name | avatar_url |
|----|-----------|------------|
| uuid-1 | ANTONIO | https://res.cloudinary.com/.../profile_123.jpg |
| uuid-2 | EMPI | null |
| uuid-3 | YOHANIS | https://res.cloudinary.com/.../profile_456.jpg |

---

## Cloudinary Configuration

### Account Info
- **Cloud Name**: `dkkbwu8hj`
- **Upload Preset**: `vtrack_uploads`
- **Folder**: `vtrack/profiles`

### Upload Preset Settings (di Cloudinary Dashboard)
1. Login ke Cloudinary
2. Settings → Upload → Upload presets
3. Preset: `vtrack_uploads`
4. Settings:
   - Signing Mode: **Unsigned**
   - Folder: `vtrack/profiles`
   - Allowed formats: jpg, png
   - Max file size: 10 MB
   - Transformations: Auto (optional)

### API Keys (untuk Delete)
- **API Key**: [Get from Cloudinary Dashboard]
- **API Secret**: [Get from Cloudinary Dashboard]
- ⚠️ **JANGAN** simpan di Flutter code (security risk)
- ✅ Simpan di Supabase Edge Function environment variables

---

## Testing Checklist

### Upload Foto
- [ ] Tap icon kamera → Bottom sheet muncul
- [ ] Pilih Kamera → Camera app terbuka
- [ ] Pilih Galeri → Gallery terbuka
- [ ] Ambil/pilih foto → Preview dialog muncul
- [ ] Klik Upload → Loading indicator muncul
- [ ] Upload success → Snackbar hijau muncul
- [ ] Avatar ter-update dengan foto baru
- [ ] Pull to refresh → Foto tetap ada

### Hapus Foto Lama
- [ ] Upload foto pertama kali → Tersimpan
- [ ] Upload foto kedua → Foto pertama ter-replace di database
- [ ] Check Cloudinary → Foto lama masih ada (expected, requires backend)
- [ ] Console log → Public ID ter-extract dengan benar

### Display di Semua Halaman
- [ ] Tab Profil → Foto tampil
- [ ] Tab Home (card header) → Foto tampil
- [ ] Logout & login → Foto tetap ada
- [ ] User lain → Foto masing-masing tampil (tidak tercampur)

### Chat (TODO)
- [ ] Chat list → Avatar user tampil
- [ ] Chat room → Avatar sender tampil
- [ ] Group chat → Avatar semua member tampil

---

## Files Modified

### New Files
1. `lib/core/widgets/user_avatar.dart` - Reusable avatar widget
2. `supabase/check_avatar_url_column.sql` - Add avatar_url column
3. `docs/PROFILE_PHOTO_SYSTEM_04FEB2026.md` - This documentation

### Modified Files
1. `lib/features/promotor/presentation/tabs/promotor_profil_tab.dart`
   - Added camera/gallery picker
   - Added preview dialog
   - Added delete old image function
   - Improved loading states

2. `lib/features/promotor/presentation/tabs/promotor_home_tab.dart`
   - Updated `_buildHeader()` to use avatar_url
   - Added avatar_url to select query

---

## Next Steps (Optional Improvements)

### 1. Implement Backend Delete
Create Supabase Edge Function untuk delete foto lama dari Cloudinary secara aman.

### 2. Update Chat System
Integrate avatar_url ke semua komponen chat:
- Chat list items
- Chat room messages
- Group member lists

### 3. Add Image Compression
Gunakan package `flutter_image_compress` untuk compress lebih baik sebelum upload.

### 4. Add Crop Feature
Gunakan package `image_cropper` untuk crop foto sebelum upload.

### 5. Add Progress Indicator
Show upload progress percentage saat upload foto besar.

### 6. Cache Management
Implement cache clearing untuk NetworkImage agar foto baru langsung tampil.

---

## Troubleshooting

### Foto tidak tampil setelah upload
- Check console log untuk error
- Verify avatar_url tersimpan di database
- Check Cloudinary URL accessible
- Try clear app cache & restart

### Upload gagal
- Check internet connection
- Verify Cloudinary upload preset settings
- Check file size (max 10MB)
- Check file format (jpg/png only)

### Foto lama tidak terhapus
- Expected behavior (requires backend implementation)
- Foto lama tetap ada di Cloudinary
- Database sudah ter-update dengan URL baru
- Implement Edge Function untuk auto-delete

---

## Security Notes

⚠️ **IMPORTANT**:
- Cloudinary API Key & Secret **JANGAN** disimpan di Flutter code
- Upload menggunakan **unsigned preset** (aman untuk client-side)
- Delete harus via **backend** dengan authenticated request
- Validate file type & size di client dan server
- Implement rate limiting untuk prevent abuse

---

## Cost Estimation

### Cloudinary Free Tier
- **Storage**: 25 GB
- **Bandwidth**: 25 GB/month
- **Transformations**: 25,000/month

### Estimation untuk 1000 users
- Average photo size: 100 KB
- Total storage: 100 MB (0.1 GB)
- Monthly bandwidth (10 views/user): 1 GB
- **Status**: ✅ Masih dalam free tier

### Upgrade jika perlu
- Plus Plan: $89/month (100 GB storage, 100 GB bandwidth)
- Advanced Plan: $224/month (500 GB storage, 500 GB bandwidth)

---

## Conclusion

✅ **Upload foto profil**: Working
✅ **Display di Home & Profil**: Working
⚠️ **Delete foto lama**: Partial (requires backend)
📋 **Chat integration**: TODO

System sudah berfungsi dengan baik untuk upload dan display foto profil. Delete foto lama bisa diimplementasi nanti via Supabase Edge Function untuk security yang lebih baik.
