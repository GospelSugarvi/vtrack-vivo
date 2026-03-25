import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../ui/foundation/app_colors.dart';

class ShiftSettingsPage extends StatefulWidget {
  const ShiftSettingsPage({super.key});

  @override
  State<ShiftSettingsPage> createState() => _ShiftSettingsPageState();
}

class _ShiftSettingsPageState extends State<ShiftSettingsPage> {
  bool _isLoading = false;
  List<String> _areas = ['default'];
  String _selectedArea = 'default';
  
  final Map<String, Map<String, TimeOfDay>> _shiftTimes = {
    'pagi': {
      'start': const TimeOfDay(hour: 8, minute: 0),
      'end': const TimeOfDay(hour: 16, minute: 0),
    },
    'siang': {
      'start': const TimeOfDay(hour: 13, minute: 0),
      'end': const TimeOfDay(hour: 21, minute: 0),
    },
    'fullday': {
      'start': const TimeOfDay(hour: 8, minute: 0),
      'end': const TimeOfDay(hour: 22, minute: 0),
    },
  };

  @override
  void initState() {
    super.initState();
    _loadAreas();
    _loadShiftSettings();
  }

  Future<void> _loadAreas() async {
    try {
      // Get unique areas from users table
      final response = await Supabase.instance.client
          .from('users')
          .select('area')
          .not('area', 'is', null);

      final Set<String> uniqueAreas = {'default'};
      for (final item in response) {
        final area = item['area'] as String?;
        if (area != null && area.isNotEmpty) {
          uniqueAreas.add(area);
        }
      }

      setState(() {
        _areas = uniqueAreas.toList()..sort();
      });
    } catch (e) {
      debugPrint('Error loading areas: $e');
    }
  }

  Future<void> _loadShiftSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await Supabase.instance.client
          .from('shift_settings')
          .select('shift_type, start_time, end_time')
          .eq('area', _selectedArea)
          .eq('active', true);

      for (final setting in response) {
        final shiftType = setting['shift_type'] as String;
        final startTime = setting['start_time'] as String;
        final endTime = setting['end_time'] as String;
        
        // Parse time strings (HH:MM:SS format)
        final startParts = startTime.split(':');
        final endParts = endTime.split(':');
        
        setState(() {
          _shiftTimes[shiftType] = {
            'start': TimeOfDay(
              hour: int.parse(startParts[0]),
              minute: int.parse(startParts[1]),
            ),
            'end': TimeOfDay(
              hour: int.parse(endParts[0]),
              minute: int.parse(endParts[1]),
            ),
          };
        });
      }
    } catch (e) {
      debugPrint('Error loading shift settings: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveShiftSettings() async {
    setState(() => _isLoading = true);
    
    try {
      // Delete existing settings for this area
      await Supabase.instance.client
          .from('shift_settings')
          .delete()
          .eq('area', _selectedArea);

      // Insert new settings
      final List<Map<String, dynamic>> settingsData = [];
      
      _shiftTimes.forEach((shiftType, times) {
        settingsData.add({
          'shift_type': shiftType,
          'start_time': '${times['start']!.hour.toString().padLeft(2, '0')}:${times['start']!.minute.toString().padLeft(2, '0')}:00',
          'end_time': '${times['end']!.hour.toString().padLeft(2, '0')}:${times['end']!.minute.toString().padLeft(2, '0')}:00',
          'area': _selectedArea,
          'active': true,
        });
      });

      await Supabase.instance.client
          .from('shift_settings')
          .insert(settingsData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pengaturan jam kerja berhasil disimpan!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectTime(String shiftType, String timeType) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _shiftTimes[shiftType]![timeType]!,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _shiftTimes[shiftType]![timeType] = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Jam Kerja'),
        backgroundColor: AppColors.infoSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Area Selection
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pilih Area:',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedArea,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: _areas.map((area) {
                              return DropdownMenuItem(
                                value: area,
                                child: Text(area == 'default' ? 'Default (Global)' : area),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedArea = value;
                                });
                                _loadShiftSettings();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Shift Settings
                  Expanded(
                    child: ListView(
                      children: [
                        _buildShiftCard('pagi', '🌅 Shift Pagi', AppColors.warning),
                        const SizedBox(height: 16),
                        _buildShiftCard('siang', '🌇 Shift Siang', Colors.purple),
                        const SizedBox(height: 16),
                        _buildShiftCard('fullday', '☀️ Shift Fullday', Colors.indigo),
                      ],
                    ),
                  ),
                  
                  // Save Button
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: ElevatedButton(
                      onPressed: _saveShiftSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.info,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Simpan Pengaturan',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildShiftCard(String shiftType, String title, Color color) {
    final times = _shiftTimes[shiftType]!;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                // Start Time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Jam Mulai:', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _selectTime(shiftType, 'start'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                times['start']!.format(context),
                                style: const TextStyle(fontSize: 16),
                              ),
                              Icon(Icons.access_time, color: color),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // End Time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Jam Selesai:', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _selectTime(shiftType, 'end'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                times['end']!.format(context),
                                style: const TextStyle(fontSize: 16),
                              ),
                              Icon(Icons.access_time, color: color),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Duration Display
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: color),
                  const SizedBox(width: 8),
                  Text(
                    'Durasi: ${_calculateDuration(times['start']!, times['end']!)} jam',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _calculateDuration(TimeOfDay start, TimeOfDay end) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    final durationMinutes = endMinutes - startMinutes;
    
    if (durationMinutes <= 0) {
      return '0';
    }
    
    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;
    
    if (minutes == 0) {
      return hours.toString();
    } else {
      return '$hours.${(minutes / 60 * 10).round()}';
    }
  }
}