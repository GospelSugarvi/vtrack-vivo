import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/chat_message.dart';
import '../theme/chat_theme.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Function(String emoji) onReactionTap;
  final VoidCallback onReplyTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.onReactionTap,
    required this.onReplyTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = chatTokensOf(context);
    final isOwn = message.isOwnMessage;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isOwn)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                message.senderName ?? 'Unknown',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.primary,
                ),
              ),
            ),
          if (message.replyToId != null) _buildReplyContext(isOwn, tokens),
          GestureDetector(
            onLongPress: () => _showMessageOptions(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isOwn ? tokens.bubbleOwn : tokens.bubbleOther,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isOwn ? 16 : 4),
                  bottomRight: Radius.circular(isOwn ? 4 : 16),
                ),
                border: isOwn
                    ? null
                    : Border.all(color: tokens.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMessageContent(isOwn, tokens),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isEdited)
                        Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Text(
                            'Edited',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                      Text(
                        DateFormat('HH:mm').format(message.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      if (isOwn && message.readByCount > 0) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.done_all,
                          size: 15,
                          color: tokens.primary,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (message.reactions != null && message.reactions!.isNotEmpty)
            _buildReactions(tokens),
        ],
      ),
    );
  }

  Widget _buildReplyContext(bool isOwn, ChatThemeTokens tokens) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isOwn
            ? tokens.surfaceAlt.withValues(alpha: 0.6)
            : tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: tokens.primary.withValues(alpha: 0.6),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replyToSenderName ?? 'Unknown',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToContent ?? 'Message',
            style: TextStyle(
              fontSize: 12,
              color: tokens.textMuted,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(bool isOwn, ChatThemeTokens tokens) {
    if (message.messageType == 'image') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              message.imageUrl!,
              width: 220,
              height: 160,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  width: 220,
                  height: 160,
                  color: tokens.background,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(tokens.primary),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                debugPrint('=== IMAGE LOAD ERROR: $error ===');
                debugPrint('=== FAILED URL: ${message.imageUrl} ===');
                return Container(
                  width: 220,
                  height: 160,
                  color: tokens.background,
                  child: Icon(Icons.broken_image, color: tokens.textMuted),
                );
              },
            ),
          ),
          if (message.content != null && message.content!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message.content!,
              style: TextStyle(fontSize: 14, color: tokens.textPrimary),
            ),
          ],
        ],
      );
    }

    return Text(
      message.content ?? '',
      style: TextStyle(fontSize: 14, color: tokens.textPrimary),
    );
  }

  Widget _buildReactions(ChatThemeTokens tokens) {
    return Container(
      margin: const EdgeInsets.only(top: 6, left: 6, right: 6),
      child: Wrap(
        spacing: 4,
        children: message.reactions!.entries.map((entry) {
          final emoji = entry.key;
          final reactionData = entry.value as Map<String, dynamic>;
          final count = reactionData['count'] as int;

          return GestureDetector(
            onTap: () => onReactionTap(emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.chipBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.chipBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 2),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: tokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: chatTokensOf(context).surfaceAlt,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.reply, color: chatTokensOf(context).textSecondary),
              title: Text('Reply',
                  style: TextStyle(color: chatTokensOf(context).textSecondary)),
              onTap: () {
                Navigator.pop(context);
                onReplyTap();
              },
            ),
            ListTile(
              leading: Icon(Icons.emoji_emotions, color: chatTokensOf(context).textSecondary),
              title: Text('Add Reaction',
                  style: TextStyle(color: chatTokensOf(context).textSecondary)),
              onTap: () {
                Navigator.pop(context);
                _showEmojiPicker(context);
              },
            ),
            if (message.isOwnMessage) ...[
              ListTile(
                leading: Icon(Icons.edit, color: chatTokensOf(context).textSecondary),
                title:
                    Text('Edit', style: TextStyle(color: chatTokensOf(context).textSecondary)),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: Icon(Icons.delete, color: chatTokensOf(context).textSecondary),
                title: Text('Delete',
                    style: TextStyle(color: chatTokensOf(context).textSecondary)),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showEmojiPicker(BuildContext context) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '😡', '👏', '🔥', '💪', '🎉'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: chatTokensOf(context).surfaceAlt,
        title: Text('Choose Reaction',
            style: TextStyle(color: chatTokensOf(context).textPrimary)),
        content: Wrap(
          spacing: 8,
          children: emojis.map((emoji) {
            return GestureDetector(
              onTap: () {
                Navigator.pop(context);
                onReactionTap(emoji);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: chatTokensOf(context).border),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
