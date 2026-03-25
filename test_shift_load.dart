// Simple test to verify shift settings loading
// Run this in main.dart temporarily to test

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

Future<void> testShiftSettings() async {
  final supabase = Supabase.instance.client;
  
  try {
    // Get current user
    final userId = supabase.auth.currentUser!.id;
    debugPrint('👤 User ID: $userId');
    
    // Get user area
    final userResponse = await supabase
        .from('users')
        .select('area, full_name')
        .eq('id', userId)
        .single();
    
    debugPrint('📍 User: ${userResponse['full_name']}, Area: ${userResponse['area']}');
    
    // Get shift settings
    final area = userResponse['area'] as String? ?? 'default';
    final response = await supabase
        .from('shift_settings')
        .select('shift_type, start_time, end_time')
        .eq('area', area)
        .eq('active', true);
    
    debugPrint('⏰ Shift settings for $area:');
    for (final setting in response) {
      debugPrint('   ${setting['shift_type']}: ${setting['start_time']} - ${setting['end_time']}');
    }
    
    if (response.isEmpty) {
      debugPrint('⚠️ No settings found for $area, trying default...');
      final defaultResponse = await supabase
          .from('shift_settings')
          .select('shift_type, start_time, end_time')
          .eq('area', 'default')
          .eq('active', true);
      
      debugPrint('⏰ Default shift settings:');
      for (final setting in defaultResponse) {
        debugPrint('   ${setting['shift_type']}: ${setting['start_time']} - ${setting['end_time']}');
      }
    }
  } catch (e, stackTrace) {
    debugPrint('❌ Error: $e');
    debugPrint('Stack: $stackTrace');
  }
}
