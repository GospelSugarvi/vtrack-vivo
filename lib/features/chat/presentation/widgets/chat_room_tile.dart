import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/chat_room.dart';
import '../theme/chat_theme.dart';

class ChatRoomTile extends StatelessWidget {
  final ChatRoom room;
  final VoidCallback onTap;

  const ChatRoomTile({super.key, required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = chatTokensOf(context);
    final c = chatPaletteOf(context);
    final isUnread = room.unreadCount > 0;
    final timeLabel = room.lastMessageTime != null
        ? _formatTime(room.lastMessageTime!)
        : '';
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUnread ? tokens.chipBg : c.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isUnread ? tokens.chipBorder : tokens.border,
          ),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _getGradientColors(c),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(
                    backgroundColor: tokens.background,
                    child: Text(
                      room.name.isNotEmpty ? room.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: c.onAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (room.isMuted)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: tokens.background,
                        shape: BoxShape.circle,
                        border: Border.all(color: tokens.border, width: 1.5),
                      ),
                      child: Icon(
                        Icons.volume_off,
                        size: 15,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.name,
                          style: TextStyle(
                            fontWeight: isUnread
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 14,
                            color: isUnread
                                ? tokens.textPrimary
                                : tokens.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (timeLabel.isNotEmpty)
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: isUnread ? tokens.primary : tokens.textMuted,
                            fontWeight: isUnread
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (room.lastMessageContent != null)
                    Text(
                      room.lastMessageSenderName != null
                          ? '${room.lastMessageSenderName}: ${room.lastMessageContent}'
                          : '${room.lastMessageContent}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isUnread
                            ? tokens.textSecondary
                            : tokens.textMuted,
                        fontWeight: isUnread
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(_getRoomIcon(), size: 15, color: tokens.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        '${room.memberCount} members',
                        style: TextStyle(fontSize: 12, color: tokens.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isUnread) ...[
              const SizedBox(width: 10),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: tokens.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    room.unreadCount > 99 ? '99+' : '${room.unreadCount}',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.onAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ] else if (room.isMuted) ...[
              const SizedBox(width: 10),
              Icon(Icons.volume_off, color: tokens.textMuted, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  List<Color> _getGradientColors(ChatUiPalette c) {
    switch (room.roomType) {
      case 'announcement':
        return [c.amber, c.gold];
      case 'toko':
        return [Color.lerp(c.green, c.gold, 0.18)!, c.green];
      case 'tim':
        return [Color.lerp(c.green, c.gold, 0.45)!, c.gold];
      case 'global':
        return [c.gold, c.goldInk];
      case 'private':
        return [c.s3, c.muted2];
      default:
        return [c.s3, c.muted2];
    }
  }

  IconData _getRoomIcon() {
    switch (room.roomType) {
      case 'announcement':
        return Icons.campaign;
      case 'toko':
        return Icons.store;
      case 'tim':
        return Icons.group;
      case 'global':
        return Icons.public;
      case 'private':
        return Icons.person;
      default:
        return Icons.chat;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      if (difference.inDays == 1) {
        return 'YESTERDAY';
      } else if (difference.inDays < 7) {
        return DateFormat('EEE').format(time).toUpperCase();
      } else {
        return DateFormat('MMM d').format(time).toUpperCase();
      }
    } else if (difference.inHours > 0) {
      return '${difference.inHours}H AGO';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}M AGO';
    } else {
      return 'JUST NOW';
    }
  }
}
