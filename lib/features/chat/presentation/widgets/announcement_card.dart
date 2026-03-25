import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/chat_message.dart';
import '../theme/chat_theme.dart';

class AnnouncementCard extends StatelessWidget {
  final ChatMessage message;

  const AnnouncementCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final tokens = chatTokensOf(context);
    final c = chatPaletteOf(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: chatPaletteOf(context).shadow,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tokens.accent,
                  Color.lerp(tokens.accent, tokens.surface, 0.28)!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.campaign, color: c.gold, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PENGUMUMAN',
                        style: TextStyle(
                          color: c.gold,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dari: ${message.senderName ?? 'Admin'}',
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.goldDim,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.gold.withValues(alpha: 0.16)),
                  ),
                  child: Text(
                    DateFormat('dd MMM yyyy').format(message.createdAt),
                    style: TextStyle(
                      color: c.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.messageType == 'image' &&
                    message.imageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      message.imageUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 200,
                          color: tokens.background,
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                tokens.primary,
                              ),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint(
                          '=== ANNOUNCEMENT IMAGE LOAD ERROR: $error ===',
                        );
                        debugPrint('=== FAILED URL: ${message.imageUrl} ===');
                        return Container(
                          height: 200,
                          color: tokens.background,
                          child: Icon(
                            Icons.broken_image,
                            size: 64,
                            color: tokens.textMuted,
                          ),
                        );
                      },
                    ),
                  ),
                  if (message.content != null && message.content!.isNotEmpty)
                    const SizedBox(height: 16),
                ],

                if (message.content != null && message.content!.isNotEmpty)
                  Text(
                    message.content!,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: tokens.textPrimary,
                    ),
                  ),
              ],
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: tokens.surfaceAlt,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 16, color: tokens.textMuted),
                const SizedBox(width: 6),
                Text(
                  DateFormat('HH:mm').format(message.createdAt),
                  style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                ),
                const Spacer(),
                if (message.readByCount > 0) ...[
                  Icon(Icons.visibility, size: 16, color: tokens.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    '${message.readByCount} telah membaca',
                    style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
