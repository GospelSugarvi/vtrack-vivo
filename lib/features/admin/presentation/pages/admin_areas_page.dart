import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';

class AdminAreasPage extends StatefulWidget {
  const AdminAreasPage({super.key});

  @override
  State<AdminAreasPage> createState() => _AdminAreasPageState();
}

class _AdminAreasPageState extends State<AdminAreasPage> {
  List<Map<String, dynamic>> _areas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('areas')
          .select('*')
          .order('area_name');
      
      if (!mounted) return;
      setState(() {
        _areas = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAreaDialog,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Area'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isDesktop ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDesktop) Text('Area Management', style: Theme.of(context).textTheme.headlineMedium),
            if (isDesktop) const SizedBox(height: 8),
            if (isDesktop) Text('Kelola daftar Area untuk sistem', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_areas.isEmpty)
              const Center(child: Text('Belum ada area'))
            else
              Card(
                child: Column(
                  children: _areas.map((area) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                      child: const Icon(Icons.location_on, color: AppTheme.primaryBlue),
                    ),
                    title: Text(area['area_name'] ?? '-'),
                    subtitle: Text('Status: ${area['status'] ?? 'active'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _showEditAreaDialog(area),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20, color: AppTheme.errorRed),
                          onPressed: () => _confirmDelete(area),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAddAreaDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Area Baru'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nama Area *'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nama area wajib diisi'), backgroundColor: AppTheme.errorRed),
                );
                return;
              }

              try {
                await supabase.from('areas').insert({
                  'area_name': nameController.text.trim(),
                });
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Area berhasil ditambahkan'), backgroundColor: AppTheme.successGreen),
                );
                _loadAreas();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showEditAreaDialog(Map<String, dynamic> area) {
    final nameController = TextEditingController(text: area['area_name']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Area'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nama Area *'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;

              try {
                await supabase.from('areas').update({
                  'area_name': nameController.text.trim(),
                }).eq('id', area['id']);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Area berhasil diupdate'), backgroundColor: AppTheme.successGreen),
                );
                _loadAreas();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> area) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Area'),
        content: Text('Yakin ingin menghapus area "${area['area_name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('areas').delete().eq('id', area['id']);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Area berhasil dihapus'), backgroundColor: AppTheme.successGreen),
        );
        _loadAreas();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
        );
      }
    }
  }
}
