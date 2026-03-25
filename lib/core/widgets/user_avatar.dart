import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Reusable avatar widget that displays user profile photo
/// Automatically uses avatar_url from user data or shows initial letter
/// Uses CachedNetworkImage for smooth performance
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String fullName;
  final double radius;
  final Color? backgroundColor;
  final Color? textColor;
  final double? fontSize;
  final bool showBorder;
  final Color? borderColor;

  const UserAvatar({
    super.key,
    this.avatarUrl,
    required this.fullName,
    this.radius = 20,
    this.backgroundColor,
    this.textColor,
    this.fontSize,
    this.showBorder = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
    final defaultBgColor = backgroundColor ?? _getColorFromName(fullName);
    final defaultTextColor = textColor ?? Colors.white;
    final defaultFontSize = fontSize ?? radius * 0.6;

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: defaultBgColor,
      backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
          ? CachedNetworkImageProvider(avatarUrl!) as ImageProvider
          : null,
      child: (avatarUrl == null || avatarUrl!.isEmpty)
          ? Text(
              initial,
              style: TextStyle(
                color: defaultTextColor,
                fontSize: defaultFontSize,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );

    if (showBorder) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: borderColor ?? Colors.white,
            width: 2,
          ),
        ),
        child: avatar,
      );
    }

    return avatar;
  }

  /// Generate consistent color from name
  Color _getColorFromName(String name) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];
    
    final hash = name.hashCode.abs();
    return colors[hash % colors.length];
  }
}
