import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

class AdminChatManagementPage extends StatefulWidget {
  const AdminChatManagementPage({super.key});

  @override
  State<AdminChatManagementPage> createState() => _AdminChatManagementPageState();
}

class _AdminChatManagementPageState extends State<AdminChatManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Broadcast tab state
  final TextEditingController _messageController = TextEditingController();
  String? _selectedRoomId;
  List<Map<String, dynamic>> _broadcastRooms = [];
  bool _isSending = false;
  XFile? _selectedImage;
  
  // Monitor tab state
  List<Map<String, dynamic>> _chatStats = [];
  bool _isLoadingStats = true;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBroadcastRooms();
    _loadChatStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadBroadcastRooms() async {
    try {
      final response = await supabase
          .from('chat_rooms')
          .select('id, room_type, name')
          .inFilter('room_type', ['global', 'announcement'])
          .order('room_type');
      
      setState(() {
        _broadcastRooms = List<Map<String, dynamic>>.from(response);
        if (_broadcastRooms.isNotEmpty) {
          _selectedRoomId = _broadcastRooms.first['id'];
        }
      });
    } catch (e) {
      debugPrint('Error loading broadcast rooms: $e');
    }
  }

  Future<void> _loadChatStats() async {
    try {
      setState(() => _isLoadingStats = true);
      
      // Get all chat rooms with member count and message count today
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
      
      final rooms = await supabase
          .from('chat_rooms')
          .select('id, room_type, name')
          .eq('is_active', true)
          .order('room_type');
      
      List<Map<String, dynamic>> stats = [];
      
      for (var room in rooms) {
        // Get member count
        final memberCount = await supabase
            .from('chat_members')
            .select('id')
            .eq('room_id', room['id'])
            .isFilter('left_at', null)
            .count();
        
        // Get message count today
        final messageCount = await supabase
            .from('chat_messages')
            .select('id')
            .eq('room_id', room['id'])
            .gte('created_at', todayStart)
            .count();
        
        stats.add({
          ...room,
          'member_count': memberCount.count,
          'message_count_today': messageCount.count,
        });
      }
      
      setState(() {
        _chatStats = stats;
        _isLoadingStats = false;
      });
    } catch (e) {
      debugPrint('Error loading chat stats: $e');
      setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _sendBroadcast() async {
    if (_messageController.text.trim().isEmpty && _selectedImage == null) {
      showErrorDialog(context, title: 'Gagal', message: 'Tulis pesan atau pilih gambar');
      return;
    }
    
    setState(() => _isSending = true);
    try {
      final adminId = Supabase.instance.client.auth.currentUser?.id;
      if (adminId == null) throw Exception('Admin not logged in');

      Map<String, dynamic>? imageData;
      if (_selectedImage != null) {
        imageData = await _uploadToCloudinary(_selectedImage!);
        if (imageData == null) throw Exception('Failed to upload image');
      }

      final content = _messageController.text.trim();
      
      for (final room in _broadcastRooms) {
        final messageData = {
          'room_id': room['id'],
          'sender_id': adminId,
          'content': content.isNotEmpty ? content : '[Gambar]',
          'message_type': imageData != null ? 'image' : 'text',
          'image_url': imageData?['url'],
          'image_width': imageData?['width'],
          'image_height': imageData?['height'],
        };
        await Supabase.instance.client.from('chat_messages').insert(messageData);
      }

      if (!mounted) return;
      showSuccessDialog(context, title: 'Berhasil', message: 'Broadcast terkirim ke ${_broadcastRooms.length} grup');
      setState(() {
        _messageController.clear();
        _selectedImage = null;
      });
      _loadChatStats();
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, title: 'Gagal', message: 'Gagal mengirim broadcast: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<Map<String, dynamic>?> _uploadToCloudinary(XFile file) async {
    try {
      final uri = Uri.parse('https://api.cloudinary.com/v1_1/dkkbwu8hj/image/upload');
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = 'vtrack_uploads'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send();
      
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonData = json.decode(responseData);
        
        return {
          'url': jsonData['secure_url'] as String,
          'width': jsonData['width'] as int?,
          'height': jsonData['height'] as int?,
        };
      }
      return null;
    } catch (e) {
      debugPrint('Error uploading to Cloudinary: $e');
      return null;
    }
  }

  void _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 70,
    );
    
    if (image != null) {
      setState(() => _selectedImage = image);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: isDesktop ? null : AppBar(
        title: const Text('Kelola Chat'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.campaign), text: 'Broadcast'),
            Tab(icon: Icon(Icons.analytics), text: 'Monitor'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (isDesktop) ...[
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Text('Kelola Chat', style: Theme.of(context).textTheme.headlineMedium),
                  const Spacer(),
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabs: const [
                      Tab(icon: Icon(Icons.campaign), text: 'Broadcast'),
                      Tab(icon: Icon(Icons.analytics), text: 'Monitor'),
                    ],
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBroadcastTab(isDesktop),
                _buildMonitorTab(isDesktop),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBroadcastTab(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                   const Icon(Icons.campaign, color: AppTheme.primaryBlue, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Kirim Pengumuman',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Room selector
              Text('Kirim ke:', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedRoomId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _broadcastRooms.map((room) {
                  final icon = room['room_type'] == 'global' 
                      ? Icons.public 
                      : Icons.campaign;
                  return DropdownMenuItem(
                    value: room['id'] as String,
                    child: Row(
                      children: [
                        Icon(icon, size: 20),
                        const SizedBox(width: 8),
                        Text(room['name'] as String),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedRoomId = value),
              ),
              
              const SizedBox(height: 20),
              
              // Message input
              Text('Pesan:', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _messageController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Tulis pengumuman di sini...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Image attachment
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text('Lampirkan Gambar'),
                  ),
                  if (_selectedImage != null) ...[
                    const SizedBox(width: 12),
                    Chip(
                      label: const Text('1 gambar dipilih'),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () => setState(() => _selectedImage = null),
                    ),
                  ],
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Send button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendBroadcast,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.primaryBlue,
                  ),
                  icon: _isSending 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send, color: Colors.white),
                  label: Text(
                    _isSending ? 'Mengirim...' : 'Kirim Pengumuman',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonitorTab(bool isDesktop) {
    if (_isLoadingStats) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // Group by room type
    final globalRooms = _chatStats.where((r) => r['room_type'] == 'global').toList();
    final announcementRooms = _chatStats.where((r) => r['room_type'] == 'announcement').toList();
    final teamRooms = _chatStats.where((r) => r['room_type'] == 'tim').toList();
    final storeRooms = _chatStats.where((r) => r['room_type'] == 'toko').toList();
    
    return RefreshIndicator(
      onRefresh: _loadChatStats,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isDesktop ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards
            _buildSummaryCards(isDesktop),
            
            const SizedBox(height: 24),
            
            // Detailed list
            if (globalRooms.isNotEmpty) ...[
              _buildRoomSection('Global Chat', Icons.public, AppColors.info, globalRooms),
              const SizedBox(height: 16),
            ],
            if (announcementRooms.isNotEmpty) ...[
              _buildRoomSection('Announcements', Icons.campaign, AppColors.warning, announcementRooms),
              const SizedBox(height: 16),
            ],
            if (teamRooms.isNotEmpty) ...[
              _buildRoomSection('Tim SATOR', Icons.groups, AppColors.success, teamRooms),
              const SizedBox(height: 16),
            ],
            if (storeRooms.isNotEmpty) ...[
              _buildRoomSection('Chat Toko', Icons.store, Colors.purple, storeRooms),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(bool isDesktop) {
    final totalRooms = _chatStats.length;
    final totalMembers = _chatStats.fold<int>(0, (sum, r) => sum + (r['member_count'] as int));
    final totalMessagesToday = _chatStats.fold<int>(0, (sum, r) => sum + (r['message_count_today'] as int));
    
    final cards = [
      _SummaryCard(
        icon: Icons.chat_bubble,
        label: 'Total Chat Rooms',
        value: totalRooms.toString(),
        color: AppColors.info,
      ),
      _SummaryCard(
        icon: Icons.people,
        label: 'Total Members',
        value: totalMembers.toString(),
        color: AppColors.success,
      ),
      _SummaryCard(
        icon: Icons.message,
        label: 'Pesan Hari Ini',
        value: totalMessagesToday.toString(),
        color: AppColors.warning,
      ),
    ];
    
    if (isDesktop) {
      return Row(
        children: cards.map((c) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildSummaryCard(c),
          ),
        )).toList(),
      );
    }
    
    return Column(
      children: cards.map((c) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildSummaryCard(c),
      )).toList(),
    );
  }

  Widget _buildSummaryCard(_SummaryCard card) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: card.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(card.icon, color: card.color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  card.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomSection(String title, IconData icon, Color color, List<Map<String, dynamic>> rooms) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${rooms.length} room(s)', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const Divider(),
            ...rooms.map((room) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(room['name'] as String),
              subtitle: Text('${room['member_count']} members'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (room['message_count_today'] as int) > 0 
                      ? Colors.green.withValues(alpha: 0.1) 
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${room['message_count_today']} pesan hari ini',
                  style: TextStyle(
                    color: (room['message_count_today'] as int) > 0 
                        ? AppColors.success 
                        : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}
