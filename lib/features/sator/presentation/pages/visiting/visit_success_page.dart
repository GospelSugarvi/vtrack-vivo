import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:go_router/go_router.dart';

import '../../../../../ui/promotor/promotor.dart';

class VisitSuccessPage extends StatelessWidget {
  const VisitSuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: t.success.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: t.success.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Icon(Icons.check_rounded, size: 36, color: t.success),
                ),
                const SizedBox(height: 20),
                Text(
                  'Visit Tersimpan!',
                  style: PromotorText.display(size: 28, color: t.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Data kunjungan toko sudah masuk dan bisa dipantau di flow visiting.',
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w600,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: t.primaryAccent,
                      foregroundColor: t.textOnAccent,
                    ),
                    onPressed: () => context.go('/sator/visiting'),
                    child: Text(
                      'Kembali ke Daftar Toko',
                      style: PromotorText.outfit(
                        size: 15,
                        weight: FontWeight.w800,
                        color: t.textOnAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: t.surface3),
                      foregroundColor: t.textPrimary,
                    ),
                    onPressed: () => context.go('/sator'),
                    child: Text(
                      'Ke Home',
                      style: PromotorText.outfit(
                        size: 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
