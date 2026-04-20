import 'dart:convert';
import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/success_dialog.dart';
import '../../../chat/models/chat_room.dart';
import '../../../chat/presentation/pages/chat_room_page.dart';
import '../../../chat/repository/chat_repository.dart';
import '../../../../ui/promotor/promotor.dart';

class ClockInPage extends StatefulWidget {
  const ClockInPage({super.key});

  @override
  State<ClockInPage> createState() => _ClockInPageState();
}

class _ClockInPageState extends State<ClockInPage> {
  static const _mainStatusOptions = [
    ('on_time', 'Tepat Waktu'),
    ('late', 'Terlambat'),
  ];
  static const _permissionTypes = [
    ('sick', 'Sakit'),
    ('personal', 'Izin Pribadi'),
    ('other', 'Izin Lainnya'),
  ];

  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  final _attendanceNoteController = TextEditingController();
  final _permissionReasonController = TextEditingController();
  final _permissionNoteController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatRepository = ChatRepository();

  FieldThemeTokens get t => context.fieldTokens;

  File? _storePhoto;
  File? _mainAttendanceProof;
  File? _permissionPhoto;
  bool _isLoadingAttendance = false;
  bool _isLoadingPermission = false;
  bool _isLoadingHistory = true;
  bool _isGettingLocation = false;
  BuildContext? _approvalSectionContext;
  Position? _position;
  String _locationStatus = 'Belum mengambil lokasi';
  String _selectedMainStatus = 'on_time';
  String _selectedPageTab = 'attendance';
  String _selectedPermissionType = 'sick';
  DateTime _selectedPermissionDate = DateTime.now();
  List<Map<String, dynamic>> _permissionHistory = <Map<String, dynamic>>[];

  bool get _needsStorePresence => true;
  bool get _needsMainProof => true;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _loadPermissionHistory();
  }

  @override
  void dispose() {
    _approvalSectionContext = null;
    _attendanceNoteController.dispose();
    _permissionReasonController.dispose();
    _permissionNoteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _todayMakassarDate() {
    final makassarNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    return DateFormat('yyyy-MM-dd').format(makassarNow);
  }

  String _formatDate(DateTime value) {
    return DateFormat('dd MMM yyyy', 'id_ID').format(value);
  }

  String _clockInStatusLabel() {
    switch (_selectedMainStatus) {
      case 'late':
        return 'Terlambat';
      case 'on_time':
      default:
        return 'Tepat Waktu';
    }
  }

  Future<ChatRoom?> _loadActiveStoreChatRoom(String userId) async {
    final assignmentRows = await _supabase
        .from('assignments_promotor_store')
        .select('store_id')
        .eq('promotor_id', userId)
        .eq('active', true)
        .order('created_at', ascending: false)
        .limit(1);
    final assignments = List<Map<String, dynamic>>.from(assignmentRows);
    final storeId = assignments.isNotEmpty
        ? '${assignments.first['store_id'] ?? ''}'.trim()
        : '';
    if (storeId.isEmpty) return null;
    return _chatRepository.getStoreChatRoom(storeId: storeId);
  }

  Future<void> _sendClockInChatNotification({
    required ChatRoom room,
    required String userId,
    required String imageUrl,
  }) async {
    final userRow = await _supabase
        .from('users')
        .select('full_name, nickname')
        .eq('id', userId)
        .maybeSingle();
    final nickname = '${userRow?['nickname'] ?? ''}'.trim();
    final fullName = '${userRow?['full_name'] ?? ''}'.trim();
    final displayName = nickname.isNotEmpty
        ? nickname
        : (fullName.isNotEmpty ? fullName : 'Promotor');
    final note = _attendanceNoteController.text.trim();
    final captionParts = <String>[
      'clock_in_success',
      displayName,
      _clockInStatusLabel(),
      if (note.isNotEmpty) note,
    ];

    await _supabase.rpc(
      'send_message',
      params: {
        'p_room_id': room.id,
        'p_sender_id': userId,
        'p_message_type': 'image',
        'p_content': captionParts.join('::'),
        'p_image_url': imageUrl,
      },
    );
  }

  Future<void> _loadPermissionHistory() async {
    if (!mounted) return;
    setState(() => _isLoadingHistory = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final rows = await _supabase
          .from('permission_requests')
          .select(
            'id, request_date, request_type, reason, note, photo_url, status, '
            'created_at, sator_comment, sator_approved_at, spv_comment, spv_approved_at, '
            'sator:sator_id(full_name), spv:spv_id(full_name)',
          )
          .eq('promotor_id', userId)
          .order('request_date', ascending: false)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _permissionHistory = List<Map<String, dynamic>>.from(rows);
        _isLoadingHistory = false;
      });
    } catch (e) {
      debugPrint('Error loading permission history: $e');
      if (!mounted) return;
      setState(() {
        _permissionHistory = <Map<String, dynamic>>[];
        _isLoadingHistory = false;
      });
    }
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
    final source = await _showImageSourceSheet();
    if (source == null) return;
    await _pickImage(
      source: source,
      onPicked: (file) => setState(() => _mainAttendanceProof = file),
    );
  }

  Future<void> _pickPermissionPhoto() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;
    await _pickImage(
      source: source,
      onPicked: (file) => setState(() => _permissionPhoto = file),
    );
  }

  Future<ImageSource?> _showImageSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: t.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.surface3,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor: t.surface2,
                  leading: Icon(
                    Icons.photo_library_rounded,
                    color: t.primaryAccent,
                  ),
                  title: Text(
                    'Ambil dari Galeri',
                    style: PromotorText.outfit(
                      size: 15,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                const SizedBox(height: 8),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor: t.surface2,
                  leading: Icon(
                    Icons.camera_alt_rounded,
                    color: t.primaryAccent,
                  ),
                  title: Text(
                    'Foto Bukti',
                    style: PromotorText.outfit(
                      size: 15,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ],
            ),
          ),
        );
      },
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

  Future<void> _pickPermissionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedPermissionDate,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 14)),
    );
    if (picked == null) return;
    setState(() => _selectedPermissionDate = picked);
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

    setState(() => _isLoadingAttendance = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
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
        'notes': _attendanceNoteController.text.trim().isNotEmpty
            ? _attendanceNoteController.text.trim()
            : null,
        'created_at': now.toIso8601String(),
      };

      await _supabase
          .from('attendance')
          .insert(payload)
          .timeout(const Duration(seconds: 15));

      ChatRoom? storeChatRoom;
      if (storePhotoUrl != null && storePhotoUrl.isNotEmpty) {
        storeChatRoom = await _loadActiveStoreChatRoom(userId);
        if (storeChatRoom != null) {
          await _sendClockInChatNotification(
            room: storeChatRoom,
            userId: userId,
            imageUrl: storePhotoUrl,
          );
        }
      }

      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Laporan Kehadiran Tersimpan',
        message: 'Bukti masuk kerja dan absensi utama sudah terkirim.',
      );
      if (!mounted) return;
      if (storeChatRoom != null) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ChatRoomPage(room: storeChatRoom!)),
        );
        return;
      }
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorDialog(
        context,
        ErrorHandler.handleError(e),
        onRetry: _submitClockIn,
      );
    } finally {
      if (mounted) setState(() => _isLoadingAttendance = false);
    }
  }

  Future<void> _submitPermission() async {
    final reason = _permissionReasonController.text.trim();
    if (reason.isEmpty) {
      ErrorHandler.showErrorSnackBar(context, 'Alasan izin wajib diisi.');
      return;
    }

    setState(() => _isLoadingPermission = true);
    try {
      String? photoUrl;
      if (_permissionPhoto != null) {
        photoUrl = await _uploadToCloudinary(
          _permissionPhoto!,
          folder: 'vtrack/attendance/permission',
          filenamePrefix: 'permission_request',
        );
      }

      final result = await _supabase.rpc(
        'submit_permission_request',
        params: {
          'p_request_date': DateFormat(
            'yyyy-MM-dd',
          ).format(_selectedPermissionDate),
          'p_request_type': _selectedPermissionType,
          'p_reason': reason,
          'p_note': _permissionNoteController.text.trim(),
          'p_photo_url': photoUrl,
        },
      );

      final payload = result is Map<String, dynamic>
          ? result
          : Map<String, dynamic>.from(result as Map);
      final success = payload['success'] == true;
      if (!success) {
        throw ValidationException(
          message: '${payload['message'] ?? 'Pengajuan izin gagal.'}',
        );
      }

      _permissionReasonController.clear();
      _permissionNoteController.clear();
      if (mounted) {
        setState(() {
          _permissionPhoto = null;
          _selectedPermissionType = 'sick';
          _selectedPermissionDate = DateTime.now();
          _selectedPageTab = 'permission';
        });
      }
      await _loadPermissionHistory();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Izin Berhasil Dikirim',
        message:
            'Pengajuan masuk ke SATOR lebih dulu. Setelah SATOR approve, SPV baru bisa approve.',
      );
      _scrollToApprovalSection();
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorDialog(
        context,
        ErrorHandler.handleError(e),
        onRetry: _submitPermission,
      );
    } finally {
      if (mounted) setState(() => _isLoadingPermission = false);
    }
  }

  void _scrollToApprovalSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _approvalSectionContext;
      if (targetContext == null || !_scrollController.hasClients) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
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

  Future<void> _openGoogleMaps(Position position) async {
    final lat = position.latitude;
    final lng = position.longitude;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ErrorHandler.showErrorSnackBar(
        context,
        'Google Maps tidak bisa dibuka di perangkat ini.',
      );
    }
  }

  String _permissionTypeLabel(String value) {
    switch (value) {
      case 'sick':
        return 'Sakit';
      case 'personal':
        return 'Izin Pribadi';
      case 'other':
        return 'Izin Lainnya';
      default:
        return value;
    }
  }

  String _permissionStatusLabel(String value) {
    switch (value) {
      case 'pending_sator':
        return 'Menunggu SATOR';
      case 'approved_sator':
        return 'Menunggu SPV';
      case 'rejected_sator':
        return 'Ditolak SATOR';
      case 'approved_spv':
        return 'Disetujui SPV';
      case 'rejected_spv':
        return 'Ditolak SPV';
      default:
        return value;
    }
  }

  Color _permissionStatusColor(String value) {
    switch (value) {
      case 'approved_spv':
        return t.success;
      case 'approved_sator':
        return t.info;
      case 'rejected_sator':
      case 'rejected_spv':
        return t.danger;
      default:
        return t.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: Container(
        color: t.background,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadPermissionHistory,
            color: t.primaryAccent,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              children: [
                _buildHeader(context, 'Foto Kehadiran'),
                const SizedBox(height: 16),
                _buildPageTabs(),
                const SizedBox(height: 16),
                if (_selectedPageTab == 'attendance')
                  _buildAttendanceContent()
                else
                  _buildPermissionContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          helperText: 'Wajib untuk laporan hadir reguler.',
          height: 172,
          compact: true,
        ),
        const SizedBox(height: 16),
        _buildSectionTitle('Bukti Absen DingTalk'),
        _buildImageCard(
          file: _mainAttendanceProof,
          onTap: _pickMainAttendanceProof,
          emptyIcon: Icons.assignment_turned_in_rounded,
          emptyText: 'Upload screenshot / foto absensi DingTalk',
          helperText: 'Bukti absensi utama tetap wajib.',
          height: 150,
          compact: true,
        ),
        const SizedBox(height: 16),
        _buildSectionTitle('Lokasi Saat Masuk'),
        _buildLocationCard(),
        const SizedBox(height: 16),
        _buildSectionTitle('Catatan Tambahan'),
        _buildTextField(
          controller: _attendanceNoteController,
          label: 'Catatan',
          hint: 'Contoh: kondisi toko, kendala masuk, atau info tambahan',
          maxLines: 3,
        ),
        const SizedBox(height: 24),
        _buildSubmitButton(
          label: 'Kirim',
          loading: _isLoadingAttendance,
          onPressed: _submitClockIn,
        ),
      ],
    );
  }

  Widget _buildPermissionContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const SizedBox.shrink(),
        ),
        const SizedBox(height: 4),
        _buildSectionTitle('Tanggal Izin'),
        _buildTapField(
          icon: Icons.event_rounded,
          label: _formatDate(_selectedPermissionDate),
          onTap: _pickPermissionDate,
        ),
        const SizedBox(height: 16),
        _buildSectionTitle('Jenis Izin'),
        _buildPermissionTypeField(),
        const SizedBox(height: 16),
        _buildSectionTitle('Alasan'),
        _buildTextField(
          controller: _permissionReasonController,
          label: 'Alasan',
          hint: 'Tulis alasan ijin',
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        _buildSectionTitle('Foto Pendukung'),
        _buildImageCard(
          file: _permissionPhoto,
          onTap: _pickPermissionPhoto,
          emptyIcon: Icons.local_hospital_rounded,
          emptyText: 'Lampirkan foto pendukung',
          helperText: 'Opsional',
          height: 220,
        ),
        const SizedBox(height: 16),
        _buildSectionTitle('Catatan Tambahan'),
        _buildTextField(
          controller: _permissionNoteController,
          label: 'Catatan',
          hint: 'Catatan tambahan',
          maxLines: 3,
        ),
        const SizedBox(height: 24),
        _buildSubmitButton(
          label: 'Kirim',
          loading: _isLoadingPermission,
          onPressed: _submitPermission,
        ),
        const SizedBox(height: 24),
        _buildLatestApprovalCard(),
        const SizedBox(height: 18),
        _buildSectionTitle('Riwayat Ijin'),
        Builder(
          builder: (context) {
            _approvalSectionContext = context;
            return _buildPermissionHistorySection();
          },
        ),
      ],
    );
  }

  Widget _buildLatestApprovalCard() {
    final latest = _permissionHistory.isNotEmpty
        ? _permissionHistory.first
        : null;
    if (latest == null) return const SizedBox.shrink();

    final status = '${latest['status'] ?? ''}';
    final statusColor = _permissionStatusColor(status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.surface3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Proses Approval Terbaru',
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _scrollToApprovalSection,
                  child: const Text('Lihat'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildApprovalTrack(
              title: 'SATOR',
              status: status == 'pending_sator'
                  ? 'Menunggu'
                  : (status == 'rejected_sator' ? 'Ditolak' : 'Approve'),
              color: status == 'pending_sator'
                  ? t.warning
                  : (status == 'rejected_sator' ? t.danger : t.success),
            ),
            const SizedBox(height: 8),
            _buildApprovalTrack(
              title: 'SPV',
              status: status == 'approved_sator'
                  ? 'Menunggu'
                  : (status == 'approved_spv'
                        ? 'Approve'
                        : (status == 'rejected_spv'
                              ? 'Ditolak'
                              : 'Belum aktif')),
              color: status == 'approved_sator'
                  ? t.warning
                  : (status == 'approved_spv'
                        ? t.success
                        : (status == 'rejected_spv' ? t.danger : t.textMuted)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _permissionStatusLabel(status),
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w800,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalTrack({
    required String title,
    required String status,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ),
        Text(
          status,
          style: PromotorText.outfit(
            size: 12,
            weight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildPageTabs() {
    final items = [('attendance', 'Kehadiran'), ('permission', 'Ijin')];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          children: items.map((item) {
            final selected = _selectedPageTab == item.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedPageTab = item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? LinearGradient(colors: [t.primaryAccent, t.warning])
                        : null,
                    color: selected ? null : t.surface1,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.$2,
                    textAlign: TextAlign.center,
                    style: PromotorText.outfit(
                      size: 14,
                      weight: FontWeight.w800,
                      color: selected ? t.textOnAccent : t.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
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

  Widget _buildPermissionTypeField() {
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
            value: _selectedPermissionType,
            isExpanded: true,
            dropdownColor: t.surface1,
            iconEnabledColor: t.primaryAccent,
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
            items: _permissionTypes.map((option) {
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
              setState(() => _selectedPermissionType = value);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required int maxLines,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: controller,
        style: PromotorText.outfit(
          size: 13,
          weight: FontWeight.w700,
          color: t.textPrimary,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: PromotorText.outfit(
            size: 15,
            weight: FontWeight.w600,
            color: t.textSecondary,
          ),
          filled: true,
          fillColor: t.surface1,
          hintText: hint,
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
        maxLines: maxLines,
      ),
    );
  }

  Widget _buildTapField({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.surface3),
          ),
          child: Row(
            children: [
              Icon(icon, color: t.primaryAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
              Icon(Icons.expand_more_rounded, color: t.textMuted),
            ],
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
    required String helperText,
    required double height,
    bool compact = false,
  }) {
    final cardRadius = compact ? 18.0 : 24.0;
    final iconSize = compact ? 34.0 : 50.0;
    final titleSize = compact ? 13.0 : 15.0;
    final helperSize = compact ? 11.0 : 12.0;
    final titlePadding = compact ? 12.0 : 16.0;
    final helperPadding = compact ? 16.0 : 20.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        height: height,
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(color: t.surface3),
        ),
        child: file == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(emptyIcon, size: iconSize, color: t.textMuted),
                  SizedBox(height: compact ? 6 : 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: titlePadding),
                    child: Text(
                      emptyText,
                      textAlign: TextAlign.center,
                      style: PromotorText.outfit(
                        size: titleSize,
                        weight: FontWeight.w700,
                        color: t.textMuted,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 4 : 6),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: helperPadding),
                    child: Text(
                      helperText,
                      textAlign: TextAlign.center,
                      style: PromotorText.outfit(
                        size: helperSize,
                        weight: FontWeight.w700,
                        color: t.textMutedStrong,
                      ),
                    ),
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(cardRadius),
                    child: Image.file(file, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: compact ? 10 : 12,
                    top: compact ? 10 : 12,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 8 : 10,
                        vertical: compact ? 5 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: t.background.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Ganti',
                        style: PromotorText.outfit(
                          size: compact ? 12 : 15,
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
    final position = _position;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      height: 200,
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.surface3),
      ),
      child: position == null
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
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(
                        position.latitude,
                        position.longitude,
                      ),
                      initialZoom: 16,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.vtrack.vtrack',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                              position.latitude,
                              position.longitude,
                            ),
                            width: 54,
                            height: 54,
                            child: Icon(
                              Icons.location_on_rounded,
                              color: t.danger,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: FilledButton.icon(
                    onPressed: () => _openGoogleMaps(position),
                    style: FilledButton.styleFrom(
                      backgroundColor: t.background.withValues(alpha: 0.82),
                      foregroundColor: t.textPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      textStyle: PromotorText.outfit(
                        size: 11,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                    icon: const Icon(Icons.map_rounded, size: 14),
                    label: const Text('Google Maps'),
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
                            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
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

  Widget _buildSubmitButton({
    required String label,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [t.primaryAccent, t.warning]),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: t.primaryAccentGlow,
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: loading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: t.surface1.withValues(alpha: 0),
              shadowColor: t.surface1.withValues(alpha: 0),
              foregroundColor: t.textOnAccent,
            ),
            child: loading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: t.textOnAccent,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Sedang mengirim',
                        style: PromotorText.outfit(
                          size: 15,
                          weight: FontWeight.w800,
                          color: t.textOnAccent,
                        ),
                      ),
                    ],
                  )
                : Text(
                    label,
                    style: PromotorText.outfit(
                      size: 16,
                      weight: FontWeight.w800,
                      color: t.textOnAccent,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionHistorySection() {
    if (_isLoadingHistory) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_permissionHistory.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.surface3),
          ),
          child: Text(
            'Belum ada pengajuan izin.',
            style: PromotorText.outfit(
              size: 14,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
        ),
      );
    }
    return Column(
      children: _permissionHistory.map(_buildPermissionHistoryCard).toList(),
    );
  }

  Widget _buildPermissionHistoryCard(Map<String, dynamic> row) {
    final status = '${row['status'] ?? ''}';
    final statusColor = _permissionStatusColor(status);
    final satorName = '${row['sator']?['full_name'] ?? 'SATOR'}';
    final spvName = '${row['spv']?['full_name'] ?? 'SPV'}';
    final createdAt = DateTime.tryParse('${row['created_at'] ?? ''}');
    final photoUrl = '${row['photo_url'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _permissionTypeLabel('${row['request_type'] ?? ''}'),
                  style: PromotorText.display(size: 17, color: t.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  _permissionStatusLabel(status),
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_formatDate(DateTime.parse('${row['request_date']}'))} • ${createdAt == null ? '-' : DateFormat('HH:mm').format(createdAt.toLocal())}',
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${row['reason'] ?? '-'}',
            style: PromotorText.outfit(
              size: 14,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          if ('${row['note'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${row['note']}',
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ],
          if (photoUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                photoUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildApprovalStep(
            title: 'Review SATOR',
            approverName: satorName,
            approvedAt: row['sator_approved_at']?.toString(),
            comment: row['sator_comment']?.toString(),
            active: status != 'pending_sator',
            approved: status == 'approved_sator' || status == 'approved_spv',
            rejected: status == 'rejected_sator',
          ),
          const SizedBox(height: 10),
          _buildApprovalStep(
            title: 'Review SPV',
            approverName: spvName,
            approvedAt: row['spv_approved_at']?.toString(),
            comment: row['spv_comment']?.toString(),
            active: [
              'approved_sator',
              'approved_spv',
              'rejected_spv',
            ].contains(status),
            approved: status == 'approved_spv',
            rejected: status == 'rejected_spv',
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalStep({
    required String title,
    required String approverName,
    required String? approvedAt,
    required String? comment,
    required bool active,
    required bool approved,
    required bool rejected,
  }) {
    final color = rejected
        ? t.danger
        : approved
        ? t.success
        : active
        ? t.warning
        : t.textMuted;
    final label = rejected
        ? 'Ditolak'
        : approved
        ? 'Approve'
        : active
        ? 'Menunggu'
        : 'Belum aktif';
    final approvedTime = approvedAt == null || approvedAt.isEmpty
        ? ''
        : DateFormat(
            'dd MMM HH:mm',
            'id_ID',
          ).format(DateTime.parse(approvedAt).toLocal());
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            approved
                ? Icons.check_circle_rounded
                : rejected
                ? Icons.cancel_rounded
                : Icons.hourglass_top_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title • $label',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  approverName,
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                if (approvedTime.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    approvedTime,
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: t.textMuted,
                    ),
                  ),
                ],
                if ((comment ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    comment!.trim(),
                    style: PromotorText.outfit(
                      size: 12,
                      weight: FontWeight.w700,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
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
