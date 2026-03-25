import 'package:flutter/material.dart';

import '../foundation/app_font_tokens.dart';
import '../foundation/app_type_scale.dart';

// =============================================================================
// PromotorColors — ALIAS LAYER ke FieldThemeTokens.dark
//
// Nilai-nilai di sini identik persis dengan FieldThemeTokens.dark.
// Kelas ini dipertahankan agar file-file lama yang menggunakannya tidak error.
//
// ⚠️  JANGAN tambah warna baru di sini.
//     Untuk widget yang punya BuildContext, gunakan:
//       final t = context.fieldTokens;
//       color: t.primaryAccent   ← lebih baik dari PromotorColors.gold
// =============================================================================
class PromotorColors {
  // Backgrounds — identik FieldThemeTokens.dark
  static const bg      = Color(0xFF1A1510);
  static const bgOuter = Color(0xFF000000);
  static const s1      = Color(0xFF211C16);
  static const s2      = Color(0xFF2A2318);
  static const s3      = Color(0xFF332B1E);
  static const s4      = Color(0xFF3D3325);

  // Accent — gold
  static const gold    = Color(0xFFC9923A);
  static const goldLt  = Color(0xFFE8B06A);
  static const goldDim = Color(0x1FC9923A);
  static const goldGlow= Color(0x47C9923A);

  // Text
  static const cream   = Color(0xFFF4EDE0);
  static const cream2  = Color(0xFFD8CFBE);
  static const muted   = Color(0xFFA89A86);
  static const muted2  = Color(0xFF7B6D59);

  // Semantic
  static const green   = Color(0xFF6AAB7A);
  static const amber   = Color(0xFFD4853A);
  static const red     = Color(0xFFC05A4A);
  static const blue    = Color(0xFF5B8DD9);
  static const purple  = Color(0xFF8B6FD4); // hanya timeline/chat
}

// =============================================================================
// PromotorText — typography helpers (dipertahankan untuk backward compat)
// Untuk kode baru gunakan AppTextStyle.xxx()
// =============================================================================
class PromotorText {
  static double _normalizeSize(double size) {
    if (size <= AppTypeScale.micro) return AppTypeScale.micro;
    if (size <= AppTypeScale.caption) return AppTypeScale.caption;
    if (size <= AppTypeScale.support) return AppTypeScale.support;
    if (size <= AppTypeScale.body) return AppTypeScale.body;
    if (size <= AppTypeScale.bodyStrong) return AppTypeScale.bodyStrong;
    if (size <= AppTypeScale.title) return AppTypeScale.title;
    if (size <= AppTypeScale.heading) return AppTypeScale.heading;
    return AppTypeScale.hero;
  }

  static TextStyle display({
    double size = AppTypeScale.heading,
    FontWeight weight = FontWeight.w900,
    Color color = PromotorColors.cream,
  }) {
    return AppFontTokens.resolve(
      AppFontRole.display,
      fontSize: _normalizeSize(size),
      fontWeight: weight,
      color: color,
      height: 1.1,
    );
  }

  static TextStyle outfit({
    double size = AppTypeScale.body,
    FontWeight weight = FontWeight.w600,
    Color color = PromotorColors.cream,
    double letterSpacing = 0,
  }) {
    return AppFontTokens.resolve(
      AppFontRole.primary,
      fontSize: _normalizeSize(size),
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }
}
