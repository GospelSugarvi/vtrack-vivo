import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key});

  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  final List<_Announcement> _announcements = [
    _Announcement(title: 'Target Januari 2026', content: 'Target bulan ini sudah ditetapkan...', date: '15 Jan 2026', isPinned: true),
    _Announcement(title: 'Promo Tahun Baru', content: 'Periode promo diperpanjang...', date: '10 Jan 2026', isPinned: false),
    _Announcement(title: 'Update Aplikasi', content: 'Versi baru tersedia...', date: '5 Jan 2026', isPinned: false),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAnnouncementDialog,
        icon: const Icon(Icons.add),
        label: const Text('Buat Pengumuman'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isDesktop ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDesktop) Text('Announcements', style: Theme.of(context).textTheme.headlineMedium),
            if (isDesktop) const SizedBox(height: 24),

            ..._announcements.map((a) => _buildAnnouncementCard(a)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncementCard(_Announcement announcement) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (announcement.isPinned)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.goldOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.push_pin, size: 15, color: AppTheme.goldOrange),
                        SizedBox(width: 4),
                        Text('Pinned', style: TextStyle(fontSize: 12, color: AppTheme.goldOrange)),
                      ],
                    ),
                  ),
                Expanded(child: Text(announcement.title, style: Theme.of(context).textTheme.titleMedium)),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'pin', child: Text(announcement.isPinned ? 'Unpin' : 'Pin')),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Hapus')),
                  ],
                  onSelected: (v) {
                    if (v == 'pin') setState(() => announcement.isPinned = !announcement.isPinned);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(announcement.content, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(announcement.date, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  void _showAddAnnouncementDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buat Pengumuman'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Judul')),
            const SizedBox(height: 12),
            TextField(controller: contentController, decoration: const InputDecoration(labelText: 'Isi'), maxLines: 3),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty) {
                setState(() {
                  _announcements.insert(0, _Announcement(
                    title: titleController.text,
                    content: contentController.text,
                    date: 'Just now',
                    isPinned: false,
                  ));
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Posting'),
          ),
        ],
      ),
    );
  }
}

class _Announcement {
  final String title;
  final String content;
  final String date;
  bool isPinned;

  _Announcement({required this.title, required this.content, required this.date, required this.isPinned});
}
