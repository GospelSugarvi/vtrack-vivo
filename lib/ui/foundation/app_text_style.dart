import 'package:flutter/material.dart';

import 'app_font_tokens.dart';
import 'app_type_scale.dart';

// =============================================================================
// AppTextStyle — Sistem tipografi terpusat
//
// Semua ukuran font menggunakan skala yang sudah baku.
// Gunakan ini sebagai ganti menulis TextStyle langsung.
//
// Cara pakai:
//   Text('Halo', style: AppTextStyle.bodyMd(t.textPrimary))
//   Text('Judul', style: AppTextStyle.headingLg(t.primaryAccent))
// =============================================================================
class AppTextStyle {
  // ─── Outfit (UI labels, body, chips) ────────────────────────────────────────

  /// 8px — label mikro, badge teks
  static TextStyle micro(Color color, {FontWeight weight = FontWeight.w600, double letterSpacing = 0}) =>
      AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.micro,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// 10px — caption kecil
  static TextStyle caption(Color color, {FontWeight weight = FontWeight.w600, double letterSpacing = 0}) =>
      AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.caption,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// 12px — label sekunder, note
  static TextStyle label(Color color, {FontWeight weight = FontWeight.w600, double letterSpacing = 0}) =>
      AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.label,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// 12px — body kecil
  static TextStyle bodySm(Color color, {FontWeight weight = FontWeight.w500, double letterSpacing = 0}) =>
      AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.bodySm,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// 14px — body standar (paling umum)
  static TextStyle bodyMd(Color color, {FontWeight weight = FontWeight.w500, double letterSpacing = 0}) =>
      AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.bodyMd,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// 16px — body besar / emphasis
  static TextStyle bodyLg(Color color, {FontWeight weight = FontWeight.w500, double letterSpacing = 0}) =>
      AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.bodyLg,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// 18px — title kecil
  static TextStyle titleSm(Color color, {FontWeight weight = FontWeight.w700, double letterSpacing = 0}) =>
      AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.titleSm,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// 18px — title sedang
  static TextStyle titleMd(Color color, {FontWeight weight = FontWeight.w700, double letterSpacing = 0}) =>
      AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.titleMd,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  // ─── Playfair Display (angka besar, heading utama) ──────────────────────────

  /// 16px — angka kecil dalam kartu
  static TextStyle numSm(Color color, {FontWeight weight = FontWeight.w800}) =>
      AppFontTokens.resolve(
        AppFontRole.display,
        fontSize: AppTypeScale.numberSm,
        fontWeight: weight,
        color: color,
        height: 1.1,
      );

  /// 18px — heading kecil
  static TextStyle headingSm(Color color, {FontWeight weight = FontWeight.w800}) =>
      AppFontTokens.resolve(
        AppFontRole.display,
        fontSize: AppTypeScale.headingSm,
        fontWeight: weight,
        color: color,
        height: 1.1,
      );

  /// 24px — heading sedang
  static TextStyle headingMd(Color color, {FontWeight weight = FontWeight.w800}) =>
      AppFontTokens.resolve(
        AppFontRole.display,
        fontSize: AppTypeScale.headingMd,
        fontWeight: weight,
        color: color,
        height: 1.1,
      );

  /// 24px — heading besar
  static TextStyle headingLg(Color color, {FontWeight weight = FontWeight.w800}) =>
      AppFontTokens.resolve(
        AppFontRole.display,
        fontSize: AppTypeScale.headingLg,
        fontWeight: weight,
        color: color,
        height: 1.1,
      );

  /// 32px — hero / angka utama dashboard
  static TextStyle heroNum(Color color, {FontWeight weight = FontWeight.w900}) =>
      AppFontTokens.resolve(
        AppFontRole.display,
        fontSize: AppTypeScale.heroNum,
        fontWeight: weight,
        color: color,
        height: 1.0,
      );

  static TextStyle mono(Color color, {double size = AppTypeScale.support, FontWeight weight = FontWeight.w500}) =>
      AppFontTokens.resolve(
        AppFontRole.mono,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.2,
      );

  static TextStyle altSans(Color color, {double size = AppTypeScale.body, FontWeight weight = FontWeight.w500}) =>
      AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: size,
        fontWeight: weight,
        color: color,
      );

  static TextStyle accent(Color color, {double size = AppTypeScale.bodyStrong, FontWeight weight = FontWeight.w700}) =>
      AppFontTokens.resolve(
        AppFontRole.accent,
        fontSize: size,
        fontWeight: weight,
        color: color,
      );
}

// =============================================================================
// Convenience extension — akses langsung dari BuildContext
//
// Cara pakai:
//   Text('Halo', style: context.textSm(t.textMuted))
// =============================================================================
extension AppTextStyleContext on BuildContext {
  /// Shorthand: micro 8px
  TextStyle textMicro(Color color, {FontWeight weight = FontWeight.w600, double ls = 0}) =>
      AppTextStyle.micro(color, weight: weight, letterSpacing: ls);

  /// Shorthand: caption 10px
  TextStyle textCaption(Color color, {FontWeight weight = FontWeight.w600}) =>
      AppTextStyle.caption(color, weight: weight);

  /// Shorthand: label 12px
  TextStyle textLabel(Color color, {FontWeight weight = FontWeight.w600}) =>
      AppTextStyle.label(color, weight: weight);

  /// Shorthand: body-sm 12px
  TextStyle textSm(Color color, {FontWeight weight = FontWeight.w500}) =>
      AppTextStyle.bodySm(color, weight: weight);

  /// Shorthand: body-md 14px
  TextStyle textMd(Color color, {FontWeight weight = FontWeight.w500}) =>
      AppTextStyle.bodyMd(color, weight: weight);

  /// Shorthand: body-lg 16px
  TextStyle textLg(Color color, {FontWeight weight = FontWeight.w500}) =>
      AppTextStyle.bodyLg(color, weight: weight);

  /// Shorthand: title-sm 18px bold
  TextStyle textTitle(Color color) => AppTextStyle.titleSm(color);

  /// Shorthand: heading number small 18px
  TextStyle textHeadSm(Color color) => AppTextStyle.headingSm(color);

  /// Shorthand: heading large 24px
  TextStyle textHeadLg(Color color) => AppTextStyle.headingLg(color);

  /// Shorthand: hero number 32px
  TextStyle textHero(Color color) => AppTextStyle.heroNum(color);
}
