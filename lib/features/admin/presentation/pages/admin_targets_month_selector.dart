import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import 'admin_targets_page_v2.dart';
import '../../../../ui/foundation/app_colors.dart';

class AdminTargetsMonthSelector extends StatefulWidget {
  const AdminTargetsMonthSelector({super.key});

  @override
  State<AdminTargetsMonthSelector> createState() => _AdminTargetsMonthSelectorState();
}

class _AdminTargetsMonthSelectorState extends State<AdminTargetsMonthSelector> {
  final int _currentYear = DateTime.now().year;
  final int _currentMonth = DateTime.now().month;
  
  final List<String> _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  final Map<int, String> _periodIds = {}; // month -> period_id
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  Future<void> _loadPeriods() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('target_periods')
          .select('id, target_month, target_year')
          .eq('target_year', _currentYear)
          .isFilter('deleted_at', null);
      
      final periods = List<Map<String, dynamic>>.from(response);
      debugPrint('[AdminTargetsMonthSelector] periods=${periods.length}');
      
      for (var period in periods) {
        final month = period['target_month'] as int;
        _periodIds[month] = period['id'] as String;
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[AdminTargetsMonthSelector] loadPeriods error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
        );
      }
    }
  }

  Future<void> _createPeriod(int month) async {
    try {
      final monthName = _monthNames[month - 1];
      final year = _currentYear;
      
      final response = await supabase.rpc('get_or_create_target_period', params: {
        'p_month': month,
        'p_year': year,
      });
      
      final periodId = response as String;
      debugPrint('[AdminTargetsMonthSelector] created period=$periodId month=$month');
      
      setState(() {
        _periodIds[month] = periodId;
      });
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdminTargetsPageV2(
              periodId: periodId,
              monthName: monthName,
              year: year,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminTargetsMonthSelector] createPeriod error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
        );
      }
    }
  }

  void _openMonth(int month) {
    final periodId = _periodIds[month];
    final monthName = _monthNames[month - 1];
    
    if (periodId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AdminTargetsPageV2(
            periodId: periodId,
            monthName: monthName,
            year: _currentYear,
          ),
        ),
      );
    } else {
      _createPeriod(month);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text('Target $_currentYear'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.5,
                ),
                itemCount: 12,
                itemBuilder: (context, index) {
                  final month = index + 1;
                  final monthName = _monthNames[index];
                  final hasPeriod = _periodIds.containsKey(month);
                  final isCurrentMonth = month == _currentMonth;
                  
                  return InkWell(
                    onTap: () => _openMonth(month),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isCurrentMonth 
                            ? AppTheme.primaryBlue.withValues(alpha: 0.1)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCurrentMonth 
                              ? AppTheme.primaryBlue
                              : AppColors.border,
                          width: isCurrentMonth ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            monthName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isCurrentMonth 
                                  ? AppTheme.primaryBlue
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (hasPeriod)
                            const Icon(
                              Icons.check_circle,
                              color: AppTheme.successGreen,
                              size: 24,
                            )
                          else
                            Icon(
                              Icons.add_circle_outline,
                              color: AppColors.borderStrong,
                              size: 24,
                            ),
                          const SizedBox(height: 4),
                          Text(
                            hasPeriod ? 'Ada Target' : 'Belum Ada',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasPeriod 
                                  ? AppTheme.successGreen
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
