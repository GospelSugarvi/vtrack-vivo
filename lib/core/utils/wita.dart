// WITA Timezone Utilities
// UTC+8 - Waktu Indonesia Tengah (Asia/Makassar)
// Use this for all date/time operations in the app.

class WitaTime {
  /// WITA offset from UTC (+8 hours)
  static const Duration offset = Duration(hours: 8);
  
  /// Get current time in WITA
  static DateTime now() {
    return DateTime.now().toUtc().add(offset);
  }
  
  /// Get today's date in WITA (no time component)
  static DateTime today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }
  
  /// Convert any DateTime to WITA
  static DateTime toWita(DateTime dt) {
    return dt.toUtc().add(offset);
  }
  
  /// Convert WITA DateTime to UTC for database storage
  static DateTime toUtc(DateTime witaTime) {
    return witaTime.subtract(offset);
  }
  
  /// Format date as Indonesian format: DD MMM YYYY
  static String formatDate(DateTime? dt) {
    if (dt == null) return '-';
    final wita = dt.isUtc ? dt.add(offset) : dt;
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 
                    'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${wita.day} ${months[wita.month - 1]} ${wita.year}';
  }
  
  /// Format datetime as: DD MMM YYYY, HH:mm
  static String formatDateTime(DateTime? dt) {
    if (dt == null) return '-';
    final wita = dt.isUtc ? dt.add(offset) : dt;
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 
                    'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'];
    final hour = wita.hour.toString().padLeft(2, '0');
    final minute = wita.minute.toString().padLeft(2, '0');
    return '${wita.day} ${months[wita.month - 1]} ${wita.year}, $hour:$minute WITA';
  }
  
  /// Format time only: HH:mm WITA
  static String formatTime(DateTime? dt) {
    if (dt == null) return '-';
    final wita = dt.isUtc ? dt.add(offset) : dt;
    final hour = wita.hour.toString().padLeft(2, '0');
    final minute = wita.minute.toString().padLeft(2, '0');
    return '$hour:$minute WITA';
  }
  
  /// Parse ISO string from Supabase to WITA DateTime
  static DateTime? parse(String? isoString) {
    if (isoString == null || isoString.isEmpty) return null;
    try {
      final utc = DateTime.parse(isoString);
      return toWita(utc);
    } catch (e) {
      return null;
    }
  }
  
  /// Get start of month in WITA
  static DateTime startOfMonth([DateTime? date]) {
    final d = date ?? now();
    return DateTime(d.year, d.month, 1);
  }
  
  /// Get end of month in WITA
  static DateTime endOfMonth([DateTime? date]) {
    final d = date ?? now();
    return DateTime(d.year, d.month + 1, 0, 23, 59, 59);
  }
}
