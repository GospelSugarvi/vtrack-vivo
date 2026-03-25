import 'package:flutter/material.dart';
import '../../../../ui/foundation/field_theme_extensions.dart';

class ChatThemeTokens {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color primary;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color bubbleOwn;
  final Color bubbleOther;
  final Color inputBg;
  final Color chipBg;
  final Color chipBorder;

  const ChatThemeTokens({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.primary,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.bubbleOwn,
    required this.bubbleOther,
    required this.inputBg,
    required this.chipBg,
    required this.chipBorder,
  });

  factory ChatThemeTokens.fromField(FieldThemeTokens field) {
    return ChatThemeTokens(
      background: field.background,
      surface: field.surface1,
      surfaceAlt: field.surface2,
      border: field.divider,
      primary: field.primaryAccent,
      accent: Color.lerp(field.surface2, field.primaryAccentSoft, 0.58)!,
      textPrimary: field.textPrimary,
      textSecondary: field.textSecondary,
      textMuted: field.textMuted,
      bubbleOwn: Color.lerp(field.primaryAccent, field.surface2, 0.68)!,
      bubbleOther: field.surface1,
      inputBg: Color.lerp(field.surface1, field.surface2, 0.36)!,
      chipBg: Color.lerp(field.primaryAccentSoft, field.surface2, 0.34)!,
      chipBorder: Color.lerp(field.primaryAccentGlow, field.divider, 0.35)!,
    );
  }
}

ChatThemeTokens chatTokensOf(BuildContext context) {
  return ChatThemeTokens.fromField(context.fieldTokens);
}

class ChatUiPalette {
  const ChatUiPalette({required this.chat, required this.field});

  final ChatThemeTokens chat;
  final FieldThemeTokens field;

  Color get bg => chat.background;
  Color get s1 => chat.surface;
  Color get s2 => chat.surfaceAlt;
  Color get s3 => chat.border;
  Color get gold => chat.primary;
  Color get goldDim => chat.chipBg;
  Color get goldGlow => chat.primary.withValues(alpha: 0.32);
  Color get cream => chat.textPrimary;
  Color get cream2 => chat.textSecondary;
  Color get muted => chat.textMuted;
  Color get muted2 => chat.textSecondary.withValues(alpha: 0.82);
  Color get green => field.success;
  Color get greenSoft => field.successSoft;
  Color get amber => field.warning;
  Color get amberSoft => field.warningSoft;
  Color get red => field.danger;
  Color get redSoft => field.dangerSoft;
  Color get blue => Color.lerp(field.info, field.primaryAccentLight, 0.36)!;
  Color get blueSoft =>
      Color.lerp(field.infoSoft, field.primaryAccentSoft, 0.52)!;
  Color get purple => Color.lerp(chat.primary, field.textSecondary, 0.26)!;
  Color get purpleSoft => Color.lerp(chat.chipBg, field.surface2, 0.45)!;
  Color get purpleDeep => Color.lerp(purple, field.textPrimary, 0.22)!;
  Color get onAccent => field.textOnAccent;
  Color get transparent => chat.surface.withValues(alpha: 0);
  Color get goldInk =>
      Color.lerp(chat.primary, field.primaryAccentLight, 0.35)!;
  Color get shadow => field.textPrimary.withValues(alpha: 0.18);
  Color get surfaceRaised => Color.lerp(chat.surface, chat.surfaceAlt, 0.5)!;
}

ChatUiPalette chatPaletteOf(BuildContext context) {
  return ChatUiPalette(chat: chatTokensOf(context), field: context.fieldTokens);
}
