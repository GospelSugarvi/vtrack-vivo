import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppNotificationBellButton extends StatefulWidget {
  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
  final Color badgeColor;
  final Color badgeTextColor;
  final double iconSize;
  final String routePath;

  const AppNotificationBellButton({
    super.key,
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.routePath,
    this.iconSize = 13,
  });

  @override
  State<AppNotificationBellButton> createState() =>
      _AppNotificationBellButtonState();
}

class _AppNotificationBellButtonState extends State<AppNotificationBellButton> {
  final _supabase = Supabase.instance.client;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final rows = await _supabase
          .from('app_notifications')
          .select('id')
          .eq('recipient_user_id', userId)
          .eq('status', 'unread')
          .isFilter('archived_at', null);

      if (!mounted) return;
      setState(() => _count = List<Map<String, dynamic>>.from(rows).length);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await context.push(widget.routePath);
    if (!mounted) return;
    await _loadCount();
  }

  @override
  Widget build(BuildContext context) {
    final badgeText = _count > 9 ? '9+' : '$_count';
    return GestureDetector(
      onTap: _openNotifications,
      child: Stack(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: widget.borderColor),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: widget.iconColor,
              size: widget.iconSize,
            ),
          ),
          if (_count > 0)
            Positioned(
              top: -1,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.badgeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: widget.badgeTextColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
