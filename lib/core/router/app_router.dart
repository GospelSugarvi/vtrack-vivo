import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/promotor/presentation/promotor_dashboard.dart';
import '../../features/sator/presentation/sator_dashboard.dart';
import '../../features/promotor/presentation/pages/clock_in_page.dart';
import '../../features/promotor/presentation/pages/sell_out_page.dart';
import '../../features/promotor/presentation/pages/stock_input_page.dart';
import '../../features/promotor/presentation/pages/cari_stok_page.dart';
import '../../features/promotor/presentation/pages/imei_normalization_page.dart';
import '../../features/promotor/presentation/pages/laporan_promosi_page.dart';
import '../../features/promotor/presentation/pages/laporan_follower_page.dart';
import '../../features/promotor/presentation/pages/laporan_allbrand_page.dart';
import '../../features/promotor/presentation/pages/laporan_allbrand_input_page.dart';
import '../../features/promotor/presentation/pages/laporan_allbrand_detail_page.dart';
import '../../features/promotor/presentation/pages/bonus_detail_page.dart';
import '../../features/promotor/presentation/pages/jadwal_bulanan_page_new.dart';
import '../../features/promotor/presentation/pages/aktivitas_harian_page.dart';
import '../../features/promotor/presentation/pages/stok_toko_page.dart';
import '../../features/promotor/presentation/pages/stok_hari_ini_page.dart';
import '../../features/promotor/presentation/pages/stock_validation_page.dart';
import '../../features/promotor/presentation/pages/rekomendasi_order_page.dart';
import '../../features/promotor/presentation/pages/leaderboard_page.dart';
import '../../features/promotor/presentation/pages/target_detail_page.dart';
import '../../features/spv/presentation/spv_dashboard.dart';
import '../../features/spv/presentation/pages/spv_allbrand_page.dart';
import '../../features/spv/presentation/pages/spv_attendance_monitor_page.dart';
import '../../features/spv/presentation/pages/spv_leaderboard_page.dart';
import '../../features/spv/presentation/pages/spv_schedule_monitor_page.dart';
import '../../features/spv/presentation/pages/spv_sellin_monitor_page.dart';
import '../../features/spv/presentation/pages/spv_sellout_monitor_page.dart';
import '../../features/spv/presentation/pages/spv_stock_management_page.dart';
import '../../features/admin/presentation/admin_dashboard.dart';
import '../../features/admin/presentation/pages/stock_rules_page.dart';
import '../../features/design/presentation/storytelling_mobile_page.dart';
import '../../features/design/presentation/ui_catalog_page.dart';
import '../../features/shared/presentation/pages/team_stock_flow_page.dart';
import '../../features/vast_finance/presentation/pages/promotor_vast_page.dart';
import '../../features/vast_finance/presentation/pages/sator_vast_page.dart';
import '../../features/vast_finance/presentation/pages/spv_vast_page.dart';

// SATOR Page Imports
import '../../features/sator/presentation/pages/sell_out/sell_out_summary_page.dart';
import '../../features/sator/presentation/pages/sell_in/sell_in_dashboard_page.dart';
import '../../features/sator/presentation/pages/sell_in/stok_gudang_page.dart';
import '../../features/sator/presentation/pages/sell_in/list_toko_page.dart';
import '../../features/sator/presentation/pages/sell_in/rekomendasi_page.dart';
import '../../features/sator/presentation/pages/sell_in/finalisasi_sellin_page.dart';
import '../../features/sator/presentation/pages/sell_in/sell_in_achievement_page.dart';
import '../../features/sator/presentation/pages/aktivitas_tim_page.dart';
import '../../features/sator/presentation/pages/leaderboard/sator_leaderboard_page.dart';
import '../../features/sator/presentation/pages/kpi_bonus_page.dart';
import '../../features/sator/presentation/pages/imei_normalisasi_page.dart';
import '../../features/sator/presentation/pages/visiting/visiting_dashboard_page.dart';
import '../../features/sator/presentation/pages/visiting/visit_form_page.dart';
import '../../features/sator/presentation/pages/visiting/visit_success_page.dart';
import '../../features/sator/presentation/pages/jadwal/jadwal_dashboard_page.dart';
import '../../features/sator/presentation/pages/export_page.dart';
import '../../features/sator/presentation/pages/sator_stock_management_page.dart';
import '../../features/sator/presentation/pages/toko_detail_page.dart';
import '../../features/sator/presentation/pages/allbrand_monitor_page.dart';
import '../../features/sator/presentation/pages/laporan_kinerja_page.dart';
import '../../features/sator/presentation/pages/riwayat_reward_page.dart';
import '../../features/sator/presentation/pages/sell_in/scan_stok_gudang_page.dart';
import '../../features/sator/presentation/pages/chip_approval_page.dart';
import '../../features/sator/presentation/tabs/sator_profil_tab.dart';
import '../../features/sator/presentation/tabs/sator_sales_tab.dart';

// Router Provider
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    routes: [
      // Splash Screen
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // Auth Routes
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),

      // UI Storytelling Preview
      GoRoute(
        path: '/design-storytelling',
        name: 'design-storytelling',
        builder: (context, state) => const StorytellingMobilePage(),
      ),
      GoRoute(
        path: '/ui-catalog',
        name: 'ui-catalog',
        builder: (context, state) => const UiCatalogPage(),
      ),

      // Promotor Routes
      GoRoute(
        path: '/promotor',
        name: 'promotor',
        builder: (context, state) => const PromotorDashboard(),
        routes: [
          GoRoute(
            path: 'clock-in',
            name: 'clock-in',
            builder: (context, state) => const ClockInPage(),
          ),
          GoRoute(
            path: 'sell-out',
            name: 'sell-out',
            builder: (context, state) => const SellOutPage(),
          ),
          GoRoute(
            path: 'stock-input',
            name: 'stock-input',
            builder: (context, state) => const StockInputPage(),
          ),
          GoRoute(
            path: 'cari-stok',
            name: 'cari-stok',
            builder: (context, state) => const CariStokPage(),
          ),
          GoRoute(
            path: 'imei-normalization',
            name: 'imei-normalization',
            builder: (context, state) => const ImeiNormalizationPage(),
          ),
          GoRoute(
            path: 'laporan-promosi',
            name: 'laporan-promosi',
            builder: (context, state) => const LaporanPromosiPage(),
          ),
          GoRoute(
            path: 'laporan-follower',
            name: 'laporan-follower',
            builder: (context, state) => const LaporanFollowerPage(),
          ),
          GoRoute(
            path: 'laporan-allbrand',
            name: 'laporan-allbrand',
            builder: (context, state) => const LaporanAllbrandPage(),
            routes: [
              GoRoute(
                path: 'input',
                name: 'laporan-allbrand-input',
                builder: (context, state) => const LaporanAllbrandInputPage(),
              ),
              GoRoute(
                path: 'detail/:reportId',
                name: 'laporan-allbrand-detail',
                builder: (context, state) => LaporanAllbrandDetailPage(
                  reportId: state.pathParameters['reportId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'bonus-detail',
            name: 'bonus-detail',
            builder: (context, state) => const BonusDetailPage(),
          ),
          GoRoute(
            path: 'jadwal-bulanan',
            name: 'jadwal-bulanan',
            builder: (context, state) => const JadwalBulananPageNew(),
          ),
          GoRoute(
            path: 'stock-validation',
            name: 'stock-validation',
            builder: (context, state) => const StockValidationPage(),
          ),
          GoRoute(
            path: 'stok-toko',
            name: 'stok-toko',
            builder: (context, state) => const StokHariIniPage(),
          ),
          GoRoute(
            path: 'stok-validasi',
            name: 'stok-validasi',
            builder: (context, state) => const StockValidationPage(),
          ),
          GoRoute(
            path: 'stok-aksi',
            name: 'stok-aksi',
            builder: (context, state) => const StokTokoPage(mode: 'actions'),
          ),
          GoRoute(
            path: 'stok-ringkasan',
            name: 'stok-ringkasan',
            builder: (context, state) => const StokTokoPage(mode: 'summary'),
          ),
          GoRoute(
            path: 'rekomendasi-order',
            name: 'rekomendasi-order',
            builder: (context, state) => const RekomendasiOrderPage(),
          ),
          GoRoute(
            path: 'leaderboard',
            name: 'leaderboard',
            builder: (context, state) => const LeaderboardPage(),
          ),
          GoRoute(
            path: 'target-detail',
            name: 'target-detail',
            builder: (context, state) => const TargetDetailPage(),
          ),
          GoRoute(
            path: 'aktivitas-harian',
            name: 'aktivitas-harian',
            builder: (context, state) => const AktivitasHarianPage(),
          ),
          GoRoute(
            path: 'vast',
            name: 'promotor-vast',
            builder: (context, state) => const PromotorVastPage(),
            routes: [
              GoRoute(
                path: 'input',
                name: 'promotor-vast-input',
                builder: (context, state) =>
                    const PromotorVastPage(inputOnly: true),
              ),
            ],
          ),
        ],
      ),

      // SATOR Routes
      GoRoute(
        path: '/sator',
        name: 'sator',
        builder: (context, state) => const SatorDashboard(),
        routes: [
          GoRoute(
            path: 'sell-out',
            name: 'sator-sell-out',
            builder: (context, state) => const SellOutSummaryPage(),
          ),
          GoRoute(
            path: 'sell-in',
            name: 'sator-sell-in',
            builder: (context, state) => const SellInDashboardPage(),
          ),
          GoRoute(
            path: 'aktivitas-tim',
            name: 'sator-aktivitas-tim',
            builder: (context, state) => const AktivitasTimPage(),
          ),
          GoRoute(
            path: 'leaderboard',
            name: 'sator-leaderboard',
            builder: (context, state) => const SatorLeaderboardPage(),
          ),
          GoRoute(
            path: 'kpi-bonus',
            name: 'sator-kpi-bonus',
            builder: (context, state) => const KpiBonusPage(),
          ),
          GoRoute(
            path: 'imei-normalisasi',
            name: 'sator-imei-normalisasi',
            builder: (context, state) => const ImeiNormalisasiPage(),
          ),
          GoRoute(
            path: 'visiting',
            name: 'sator-visiting',
            builder: (context, state) => const VisitingDashboardPage(),
          ),
          GoRoute(
            path: 'jadwal',
            name: 'sator-jadwal',
            builder: (context, state) => const JadwalDashboardPage(),
          ),
          GoRoute(
            path: 'export',
            name: 'sator-export',
            builder: (context, state) => const ExportPage(),
          ),
          GoRoute(
            path: 'allbrand',
            name: 'sator-allbrand',
            builder: (context, state) => const AllbrandMonitorPage(),
          ),
          // Sell In Detail Routes
          GoRoute(
            path: 'sell-in/gudang',
            name: 'sator-stok-gudang',
            builder: (context, state) => const StokGudangPage(),
            routes: [
              GoRoute(
                path: 'scan',
                name: 'sator-scan-gudang',
                builder: (context, state) {
                  final params = state.extra is Map<String, dynamic>
                      ? state.extra as Map<String, dynamic>
                      : null;
                  return ScanStokGudangPage(params: params);
                },
              ),
            ],
          ),
          GoRoute(
            path: 'sell-in/toko',
            name: 'sator-list-toko',
            builder: (context, state) => const ListTokoPage(),
          ),
          GoRoute(
            path: 'sell-in/rekomendasi/:storeId',
            name: 'sator-rekomendasi',
            builder: (context, state) =>
                RekomendasiPage(storeId: state.pathParameters['storeId']),
          ),
          GoRoute(
            path: 'sell-in/rekomendasi-group/:groupId',
            name: 'sator-rekomendasi-group',
            builder: (context, state) =>
                RekomendasiPage(groupId: state.pathParameters['groupId']),
          ),
          GoRoute(
            path: 'sell-in/rekomendasi',
            name: 'sator-rekomendasi-all',
            builder: (context, state) => const RekomendasiPage(),
          ),
          GoRoute(
            path: 'sell-in/finalisasi',
            name: 'sator-finalisasi-sellin',
            builder: (context, state) => const FinalisasiSellInPage(),
          ),
          GoRoute(
            path: 'sell-in/achievement',
            name: 'sator-sellin-achievement',
            builder: (context, state) => const SellInAchievementPage(),
          ),
          GoRoute(
            path: 'chip-approval',
            name: 'sator-chip-approval',
            builder: (context, state) => const ChipApprovalPage(),
          ),
          GoRoute(
            path: 'stock-management',
            name: 'sator-stock-management',
            builder: (context, state) => const SatorStockManagementPage(),
          ),
          GoRoute(
            path: 'stock-flow',
            name: 'sator-stock-flow',
            builder: (context, state) =>
                const TeamStockFlowPage(scope: 'sator'),
          ),
          // Visiting Routes
          GoRoute(
            path: 'visiting/form/:storeId',
            name: 'sator-visit-form',
            builder: (context, state) =>
                VisitFormPage(storeId: state.pathParameters['storeId']!),
          ),
          GoRoute(
            path: 'visiting/success',
            name: 'sator-visit-success',
            builder: (context, state) => const VisitSuccessPage(),
          ),
          // Toko Detail
          GoRoute(
            path: 'toko/:storeId',
            name: 'sator-toko-detail',
            builder: (context, state) =>
                TokoDetailPage(storeId: state.pathParameters['storeId']!),
          ),
          // Profile Routes
          GoRoute(
            path: 'profil',
            name: 'sator-profil',
            builder: (context, state) => const SatorProfilTab(),
          ),
          GoRoute(
            path: 'laporan-kinerja',
            name: 'sator-laporan-kinerja',
            builder: (context, state) => const LaporanKinerjaPage(),
          ),
          GoRoute(
            path: 'riwayat-reward',
            name: 'sator-riwayat-reward',
            builder: (context, state) => const RiwayatRewardPage(),
          ),
          GoRoute(
            path: 'reports-sellout-tim',
            name: 'sator-reports-sellout-tim',
            builder: (context, state) {
              final tab = state.uri.queryParameters['tab']?.toLowerCase();
              final initialReportTab = switch (tab) {
                'weekly' => 1,
                'monthly' => 2,
                _ => 0,
              };
              return SatorSalesTab(
                reportsOnly: true,
                initialReportTab: initialReportTab,
              );
            },
          ),
          GoRoute(
            path: 'vast',
            name: 'sator-vast',
            builder: (context, state) => const SatorVastPage(),
          ),
        ],
      ),

      // SPV Routes
      GoRoute(
        path: '/spv',
        name: 'spv',
        builder: (context, state) => const SpvDashboard(),
        routes: [
          GoRoute(
            path: 'vast',
            name: 'spv-vast',
            builder: (context, state) => const SpvVastPage(),
          ),
          GoRoute(
            path: 'stock-management',
            name: 'spv-stock-management',
            builder: (context, state) => const SpvStockManagementPage(),
          ),
          GoRoute(
            path: 'leaderboard',
            name: 'spv-leaderboard',
            builder: (context, state) => const SpvLeaderboardPage(),
          ),
          GoRoute(
            path: 'jadwal-monitor',
            name: 'spv-jadwal-monitor',
            builder: (context, state) => const SpvScheduleMonitorPage(),
          ),
          GoRoute(
            path: 'attendance-monitor',
            name: 'spv-attendance-monitor',
            builder: (context, state) => const SpvAttendanceMonitorPage(),
          ),
          GoRoute(
            path: 'sellin-monitor',
            name: 'spv-sellin-monitor',
            builder: (context, state) => const SpvSellInMonitorPage(),
          ),
          GoRoute(
            path: 'sellout-monitor',
            name: 'spv-sellout-monitor',
            builder: (context, state) => const SpvSellOutMonitorPage(),
          ),
          GoRoute(
            path: 'allbrand',
            name: 'spv-allbrand',
            builder: (context, state) => const SpvAllbrandPage(),
          ),
          GoRoute(
            path: 'stock-flow',
            name: 'spv-stock-flow',
            builder: (context, state) => const TeamStockFlowPage(scope: 'spv'),
          ),
        ],
      ),

      // Admin Routes
      GoRoute(
        path: '/admin',
        name: 'admin',
        builder: (context, state) => const AdminDashboard(),
        routes: [
          GoRoute(
            path: 'stock-rules',
            name: 'admin-stock-rules',
            builder: (context, state) => const StockRulesPage(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Halaman tidak ditemukan',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              state.uri.toString(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Kembali ke Home'),
            ),
          ],
        ),
      ),
    ),
  );
});
