# Cloudinary Setup Guide

## 1. Create Cloudinary Account

1. Go to https://cloudinary.com/
2. Sign up for FREE account (25 GB storage, 25 GB bandwidth/month)
3. Verify your email

## 2. Get Your Credentials

After login, go to Dashboard:
- **Cloud Name**: dkkbwu8hj
- **API Key**: 426559684374596
- **API Secret**: WmPLC3-BZq7yQeEjJCs6txUqtQw

## 3. Create Upload Preset

1. Go to **Settings** → **Upload**
2. Scroll to **Upload presets**
3. Click **Add upload preset**
4. Configure:
   - **Preset name**: `vtrack_uploads` (or any name you like)
   - **Signing Mode**: **Unsigned** (important!)
   - **Folder**: `vtrack` (optional, for organization)
   - **Access mode**: **Public**
   - **Unique filename**: **true**
   - **Overwrite**: **false**
5. Click **Save**

## 4. Update Flutter Code

Open these files and replace the Cloudinary credentials:

### File: `lib/features/promotor/presentation/pages/laporan_promosi_page.dart`

```dart
// Line 18-19
static const String cloudinaryCloudName = 'YOUR_CLOUD_NAME'; // Replace with your cloud name
static const String cloudinaryUploadPreset = 'vtrack_uploads'; // Replace with your preset name
```

### File: `lib/features/promotor/presentation/pages/laporan_follower_page.dart`

```dart
// Line 18-19
static const String cloudinaryCloudName = 'YOUR_CLOUD_NAME'; // Replace with your cloud name
static const String cloudinaryUploadPreset = 'vtrack_uploads'; // Replace with your preset name
```

## 5. Image Compression Settings

Images are automatically compressed before upload:
- **Max width**: 1200px (larger images are resized)
- **Quality**: 85% (good balance between quality and file size)
- **Format**: JPEG (smaller than PNG)

This saves ~70-80% storage compared to original images!

## 6. Folder Structure in Cloudinary

Images will be organized as:
```
vtrack/
├── promotions/     # Promotion screenshots
└── followers/      # Follower screenshots
```

## 7. Free Tier Limits

Cloudinary Free Plan:
- ✅ 25 GB storage
- ✅ 25 GB bandwidth/month
- ✅ 25,000 transformations/month
- ✅ Unlimited images

With compression, you can store approximately:
- **~50,000 images** (assuming 500KB per compressed image)

## 8. Security Best Practices

1. **Never commit API Secret** to git
2. Use **unsigned upload preset** for mobile apps
3. Set **folder restrictions** in upload preset
4. Enable **rate limiting** in Cloudinary dashboard
5. Monitor usage in Dashboard → Reports

## 9. Testing

Test upload with a sample image:
1. Open app → Laporan → Lapor Promosi
2. Select platform (TikTok)
3. Pick an image
4. Submit
5. Check Cloudinary Dashboard → Media Library

## 10. Troubleshooting

**Error: "Upload failed"**
- Check cloud name and preset name are correct
- Ensure preset is set to "Unsigned"
- Check internet connection

**Error: "Image too large"**
- Compression should handle this automatically
- Check if image library is installed: `flutter pub get`

**Images not showing in Cloudinary**
- Check folder name in upload preset
- Verify upload preset is active
- Check API limits in Dashboard

## 11. Alternative: Supabase Storage

If you prefer to use Supabase Storage instead of Cloudinary:

1. Enable Storage in Supabase Dashboard
2. Create bucket: `promotion-images`
3. Set bucket to public
4. Update Flutter code to use Supabase Storage API

Benefits of Cloudinary:
- ✅ Better image optimization
- ✅ CDN delivery (faster)
- ✅ More free storage (25GB vs 1GB)
- ✅ Automatic transformations

Benefits of Supabase Storage:
- ✅ All in one place
- ✅ Easier RLS policies
- ✅ No external dependency

Choose based on your needs!
