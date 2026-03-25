import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/success_dialog.dart';
import '../../../../ui/promotor/promotor.dart';

class ClockInPage extends StatefulWidget {
  const ClockInPage({super.key});

  @override
  State<ClockInPage> createState() => _ClockInPageState();
}

class _ClockInPageState extends State<ClockInPage> {
  FieldThemeTokens get t => context.fieldTokens;
  static const _mainStatusOptions = [
    ('on_time', 'Tepat Waktu'),
    ('late', 'Terlambat'),
  ];

  final _picker = ImagePicker();
  final _noteController = TextEditingController();

  File? _storePhoto;
  File? _mainAttendanceProof;
  bool _isLoading = false;
  bool _isGettingLocation = false;
  Position? _position;
  String _locationStatus = 'Belum mengambil lokasi';
  int _mapProviderIndex = 0;
  String _selectedMainStatus = 'on_time';

  bool get _needsStorePresence => true;
  bool get _needsMainProof => true;

  String _todayMakassarDate() {
    final makassarNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    return '${makassarNow.year.toString().padLeft(4, '0')}-${makassarNow.month.toString().padLeft(2, '0')}-${makassarNow.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
      _locationStatus = 'Mengambil lokasi...';
    });

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationStatus = 'Izin lokasi ditolak';
            _isGettingLocation = false;
          });
          if (!mounted) return;
          ErrorHandler.showErrorSnackBar(
            context,
            'Izin lokasi ditolak. Aktifkan izin lokasi untuk laporan kehadiran.',
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationStatus =
              'Izin lokasi ditolak permanen. Aktifkan di Settings.';
          _isGettingLocation = false;
        });
        if (!mounted) return;
        ErrorHandler.showErrorDialog(
          context,
          PermissionException(
            message:
                'Izin lokasi ditolak permanen. Aktifkan di Pengaturan > Aplikasi > VTrack > Izin > Lokasi.',
          ),
        );
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationStatus = 'GPS tidak aktif. Nyalakan GPS.';
          _isGettingLocation = false;
        });
        if (!mounted) return;
        ErrorHandler.showErrorDialog(
          context,
          ValidationException(
            message: 'GPS tidak aktif. Silakan nyalakan GPS di perangkat Anda.',
          ),
        );
        return;
      }

      final position =
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          ).timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException(
              message: 'Waktu mengambil lokasi habis. Pastikan GPS aktif.',
            ),
          );

      setState(() {
        _position = position;
        _locationStatus =
            'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}';
        _isGettingLocation = false;
        _mapProviderIndex = 0;
      });
    } on TimeoutException catch (e) {
      setState(() {
        _locationStatus = 'Gagal ambil lokasi: Waktu habis';
        _isGettingLocation = false;
      });
      if (mounted) {
        ErrorHandler.showErrorDialog(context, e);
      }
    } on MissingPluginException {
      setState(() {
        _locationStatus = 'Fitur lokasi belum aktif di aplikasi ini';
        _isGettingLocation = false;
      });
      if (!mounted) return;
      ErrorHandler.showErrorDialog(
        context,
        AppException(
          'Plugin lokasi belum termuat. Tutup aplikasi sepenuhnya lalu buka lagi.',
        ),
      );
    } catch (e) {
      setState(() {
        _locationStatus = 'Gagal ambil lokasi: $e';
        _isGettingLocation = false;
      });
      if (mounted) {
        ErrorHandler.showErrorDialog(context, ErrorHandler.handleError(e));
      }
    }
  }

  Future<void> _pickStorePhoto() async {
    await _pickImage(
      source: ImageSource.camera,
      onPicked: (file) => setState(() => _storePhoto = file),
      preferredCameraDevice: CameraDevice.front,
    );
  }

  Future<void> _pickMainAttendanceProof() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: t.surface1,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.photo_library_rounded,
                  color: t.primaryAccent,
                ),
                title: Text(
                  'Ambil dari Galeri',
                  style: PromotorText.outfit(size: 15, weight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_rounded, color: t.primaryAccent),
                title: Text(
                  'Foto Bukti',
                  style: PromotorText.outfit(size: 15, weight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return;
    await _pickImage(
      source: source,
      onPicked: (file) => setState(() => _mainAttendanceProof = file),
    );
  }

  Future<void> _pickImage({
    required ImageSource source,
    required ValueChanged<File> onPicked,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
  }) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1280,
        maxHeight: 1600,
        preferredCameraDevice: preferredCameraDevice,
      );
      if (picked == null) return;
      onPicked(File(picked.path));
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorDialog(context, ErrorHandler.handleError(e));
    }
  }

  Future<void> _submitClockIn() async {
    if (_needsStorePresence && _storePhoto == null) {
      ErrorHandler.showErrorSnackBar(
        context,
        'Foto masuk di toko wajib diisi.',
      );
      return;
    }
    if (_needsStorePresence && _position == null) {
      ErrorHandler.showErrorSnackBar(
        context,
        'Lokasi toko belum didapat. Coba refresh lokasi.',
      );
      return;
    }
    if (_needsMainProof && _mainAttendanceProof == null) {
      ErrorHandler.showErrorSnackBar(
        context,
        'Bukti absensi utama wajib diisi.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw SessionExpiredException();
      }

      final attendanceDate = _todayMakassarDate();
      String? storePhotoUrl;
      String? mainProofUrl;

      if (_storePhoto != null) {
        storePhotoUrl = await _uploadToCloudinary(
          _storePhoto!,
          folder: 'vtrack/attendance/store',
          filenamePrefix: 'store_attendance',
        );
      }
      if (_mainAttendanceProof != null) {
        mainProofUrl = await _uploadToCloudinary(
          _mainAttendanceProof!,
          folder: 'vtrack/attendance/main-proof',
          filenamePrefix: 'main_attendance',
        );
      }

      final now = DateTime.now();
      final payload = <String, dynamic>{
        'user_id': userId,
        'attendance_date': attendanceDate,
        'photo_url': storePhotoUrl,
        'main_attendance_proof_url': mainProofUrl,
        'main_attendance_status': _selectedMainStatus,
        'clock_in': now.toIso8601String(),
        'clock_in_location': _needsStorePresence && _position != null
            ? {'lat': _position!.latitude, 'lng': _position!.longitude}
            : null,
        'notes': _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : null,
        'created_at': now.toIso8601String(),
      };

      await Supabase.instance.client
          .from('attendance')
          .insert(payload)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Laporan Kehadiran Tersimpan',
        message: _needsStorePresence
            ? 'Bukti masuk kerja dan absensi utama sudah terkirim.'
            : 'Laporan kehadiran hari ini sudah terkirim.',
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorDialog(
        context,
        ErrorHandler.handleError(e),
        onRetry: _submitClockIn,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _uploadToCloudinary(
    File imageFile, {
    required String folder,
    required String filenamePrefix,
  }) async {
    try {
      final compressedBytes = await _compressForUpload(imageFile);
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/dkkbwu8hj/image/upload',
      );
      const maxAttempts = 3;

      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        final request = http.MultipartRequest('POST', uri)
          ..fields['upload_preset'] = 'vtrack_uploads'
          ..fields['folder'] = folder
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              compressedBytes,
              filename:
                  '${filenamePrefix}_${DateTime.now().millisecondsSinceEpoch}.jpg',
            ),
          );

        final response = await request.send().timeout(
          const Duration(seconds: 40),
          onTimeout: () => throw TimeoutException(message: 'Upload timeout'),
        );

        if (response.statusCode == 200) {
          final responseData = await response.stream.toBytes();
          final result = json.decode(String.fromCharCodes(responseData));
          return result['secure_url']?.toString();
        }

        await response.stream.drain();
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }
        throw AppException('Upload gagal: ${response.statusCode}');
      }
      return null;
    } on SocketException catch (e) {
      throw NetworkException(originalError: e);
    } catch (e) {
      throw AppException('Gagal upload foto: $e', originalError: e);
    }
  }

  Future<List<int>> _compressForUpload(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    var resized = decoded;
    if (decoded.width > 960) {
      resized = img.copyResize(decoded, width: 960);
    }
    return img.encodeJpg(resized, quality: 65);
  }

  List<String> _buildMapUrls(Position position) {
    final lat = position.latitude;
    final lng = position.longitude;
    return [
      'https://static-maps.yandex.ru/1.x/?lang=id_ID&ll=$lng,$lat&z=16&size=650,350&l=map&pt=$lng,$lat,pm2rdm',
      'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng&zoom=16&size=600x400&markers=$lat,$lng,red-pushpin',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: Container(
        color: t.background,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, 'Kehadiran Harian'),
                const SizedBox(height: 16),
                _buildSectionTitle('Jenis Kehadiran'),
                _buildCategoryField(),
                const SizedBox(height: 16),
                _buildSectionTitle('Status Kehadiran'),
                _buildMainStatusField(),
                const SizedBox(height: 16),
                _buildSectionTitle('Foto Masuk'),
                _buildImageCard(
                  file: _storePhoto,
                  onTap: _pickStorePhoto,
                  emptyIcon: Icons.storefront_rounded,
                  emptyText: 'Ambil foto masuk di toko',
                  height: 280,
                ),
                const SizedBox(height: 16),
                _buildSectionTitle('Lokasi Saat Masuk'),
                _buildLocationCard(),
                const SizedBox(height: 16),
                _buildSectionTitle('Bukti Absen DingTalk'),
                _buildImageCard(
                  file: _mainAttendanceProof,
                  onTap: _pickMainAttendanceProof,
                  emptyIcon: Icons.assignment_turned_in_rounded,
                  emptyText: 'Upload screenshot / foto absensi DingTalk',
                  height: 220,
                ),
                const SizedBox(height: 16),
                _buildSectionTitle('Catatan Tambahan'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _noteController,
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Catatan',
                      labelStyle: PromotorText.outfit(
                        size: 15,
                        weight: FontWeight.w600,
                        color: t.textSecondary,
                      ),
                      filled: true,
                      fillColor: t.surface1,
                      hintText: _needsStorePresence
                          ? 'Contoh: kondisi toko, kendala masuk, atau info tambahan'
                          : 'Contoh: alasan sakit, izin pribadi, atau info libur management',
                      hintStyle: PromotorText.outfit(
                        size: 15,
                        weight: FontWeight.w700,
                        color: t.textMutedStrong,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: t.surface3),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: t.surface3),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: t.primaryAccent),
                      ),
                    ),
                    maxLines: 3,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [t.primaryAccent, t.warning],
                        ),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: t.primaryAccentGlow,
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitClockIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.surface1.withValues(alpha: 0),
                          shadowColor: t.surface1.withValues(alpha: 0),
                          foregroundColor: t.textOnAccent,
                        ),
                        child: _isLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: t.textOnAccent,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'KIRIM KEHADIRAN',
                                style: PromotorText.outfit(
                                  size: 16,
                                  weight: FontWeight.w800,
                                  color: t.textOnAccent,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 13,
          weight: FontWeight.w700,
          color: t.textPrimary,
        ),
      ),
    );
  }

  Widget _buildCategoryField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          children: [
            Icon(Icons.login_rounded, color: t.primaryAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Masuk Kerja',
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: t.primaryAccentSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.primaryAccentGlow),
              ),
              child: Text(
                'Tetap',
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w800,
                  color: t.primaryAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStatusField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.surface3),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedMainStatus,
            isExpanded: true,
            dropdownColor: t.surface1,
            iconEnabledColor: t.primaryAccent,
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
            items: _mainStatusOptions.map((option) {
              return DropdownMenuItem<String>(
                value: option.$1,
                child: Text(
                  option.$2,
                  style: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedMainStatus = value);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildImageCard({
    required File? file,
    required VoidCallback onTap,
    required IconData emptyIcon,
    required String emptyText,
    required double height,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        height: height,
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: t.surface3),
        ),
        child: file == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(emptyIcon, size: 50, color: t.textMuted),
                  const SizedBox(height: 8),
                  Text(
                    emptyText,
                    textAlign: TextAlign.center,
                    style: PromotorText.outfit(
                      size: 15,
                      weight: FontWeight.w700,
                      color: t.textMuted,
                    ),
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.file(file, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: t.background.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Ganti',
                        style: PromotorText.outfit(
                          size: 15,
                          weight: FontWeight.w800,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      height: 200,
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.surface3),
      ),
      child: _position == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isGettingLocation)
                    CircularProgressIndicator(color: t.primaryAccent)
                  else
                    Icon(Icons.location_off, size: 50, color: t.textMuted),
                  const SizedBox(height: 8),
                  Text(
                    _locationStatus,
                    textAlign: TextAlign.center,
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w700,
                      color: t.textMuted,
                    ),
                  ),
                  if (!_isGettingLocation)
                    TextButton.icon(
                      onPressed: _getCurrentLocation,
                      icon: Icon(Icons.refresh, color: t.primaryAccent),
                      label: Text(
                        'Refresh Lokasi',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.primaryAccent,
                        ),
                      ),
                    ),
                ],
              ),
            )
          : Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.network(
                    _buildMapUrls(_position!)[_mapProviderIndex],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: t.textSecondary,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: t.primaryAccent,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      final urls = _buildMapUrls(_position!);
                      if (_mapProviderIndex < urls.length - 1) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() => _mapProviderIndex++);
                        });
                      }
                      return Container(
                        color: t.surface2,
                        alignment: Alignment.center,
                        child: Text(
                          _locationStatus,
                          textAlign: TextAlign.center,
                          style: PromotorText.outfit(
                            size: 13,
                            weight: FontWeight.w600,
                            color: t.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: t.background.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: t.textOnAccent,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${_position!.latitude.toStringAsFixed(6)}, ${_position!.longitude.toStringAsFixed(6)}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textOnAccent,
                              fontSize: AppTypeScale.body,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    final t = context.fieldTokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: t.background,
        border: Border(bottom: BorderSide(color: t.surface2)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.surface3),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: t.textSecondary,
                size: 17,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: PromotorText.display(size: 18, color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
