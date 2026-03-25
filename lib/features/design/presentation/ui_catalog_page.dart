import 'package:flutter/material.dart';

import '../../../ui/components/app_badge.dart';
import '../../../ui/components/app_button.dart';
import '../../../ui/components/app_card.dart';
import '../../../ui/components/app_empty_state.dart';
import '../../../ui/components/app_info_banner.dart';
import '../../../ui/components/app_input.dart';
import '../../../ui/components/app_list_item.dart';
import '../../../ui/components/app_section_header.dart';
import '../../../ui/foundation/app_layout.dart';
import '../../../ui/foundation/app_spacing.dart';
import '../../../ui/patterns/app_action_tile.dart';
import '../../../ui/patterns/app_metric_row.dart';
import '../../../ui/patterns/app_page_header.dart';
import '../../../ui/patterns/app_stat_card.dart';
import '../../../ui/patterns/app_summary_hero.dart';

class UiCatalogPage extends StatelessWidget {
  const UiCatalogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UI Catalog')),
      body: AppPageContainer(
        child: ListView(
          children: const [
            AppPageHeader(
              title: 'UI Catalog',
              subtitle:
                  'Halaman ini menampilkan token, komponen, dan pattern yang resmi dipakai di app.',
              badgeLabel: 'Foundation',
            ),
            SizedBox(height: AppSpace.xl),
            _HeroExamples(),
            SizedBox(height: AppSpace.xl),
            AppSectionHeader(
              title: 'Buttons',
              subtitle:
                  'Variant dasar untuk action primer, sekunder, dan destruktif.',
            ),
            SizedBox(height: AppSpace.md),
            _ButtonExamples(),
            SizedBox(height: AppSpace.xl),
            AppSectionHeader(
              title: 'Cards & Banners',
              subtitle:
                  'Card resmi untuk summary, emphasis state, dan status informasi.',
            ),
            SizedBox(height: AppSpace.md),
            _CardExamples(),
            SizedBox(height: AppSpace.xl),
            AppSectionHeader(
              title: 'Lists, Badges, Metrics',
              subtitle: 'Pattern item list dan indikator status.',
            ),
            SizedBox(height: AppSpace.md),
            _ListExamples(),
            SizedBox(height: AppSpace.xl),
            AppSectionHeader(
              title: 'Action Tiles',
              subtitle: 'Pattern resmi untuk workplace/menu grid.',
            ),
            SizedBox(height: AppSpace.md),
            _ActionExamples(),
            SizedBox(height: AppSpace.xl),
            AppSectionHeader(
              title: 'Inputs & Empty State',
              subtitle: 'Komponen form dasar dan state kosong standar.',
            ),
            SizedBox(height: AppSpace.md),
            _InputExamples(),
          ],
        ),
      ),
    );
  }
}

class _HeroExamples extends StatelessWidget {
  const _HeroExamples();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        AppSummaryHero(
          eyebrow: 'Overview',
          title: 'Area Performance Snapshot',
          description:
              'Pattern hero ini dipakai untuk ringkasan area, dashboard role, dan summary screen.',
          metrics: [
            SizedBox(
              width: 160,
              child: AppMetricRow(label: 'Promotor', value: '24 aktif'),
            ),
            SizedBox(
              width: 160,
              child: AppMetricRow(label: 'Visit', value: '18 bulan ini'),
            ),
            SizedBox(
              width: 160,
              child: AppMetricRow(label: 'Achv', value: '82%'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ButtonExamples extends StatelessWidget {
  const _ButtonExamples();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        AppButton(label: 'Primary Action', isExpanded: true),
        SizedBox(height: AppSpace.sm),
        AppButton(
          label: 'Secondary Action',
          variant: AppButtonVariant.secondary,
          isExpanded: true,
        ),
        SizedBox(height: AppSpace.sm),
        AppButton(
          label: 'Danger Action',
          variant: AppButtonVariant.danger,
          isExpanded: true,
        ),
      ],
    );
  }
}

class _CardExamples extends StatelessWidget {
  const _CardExamples();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        AppCard(child: Text('Default card untuk summary umum.')),
        SizedBox(height: AppSpace.md),
        AppCard(
          tone: AppCardTone.primary,
          child: Text('Primary card untuk highlight penting.'),
        ),
        SizedBox(height: AppSpace.md),
        AppCard(
          tone: AppCardTone.warning,
          child: Text('Warning card untuk kebutuhan perhatian.'),
        ),
        SizedBox(height: AppSpace.md),
        AppInfoBanner(
          title: 'Perlu Tindakan',
          message:
              'Gunakan banner ini untuk state sistem, notifikasi page, atau warning operasional.',
          variant: AppInfoBannerVariant.warning,
        ),
      ],
    );
  }
}

class _ListExamples extends StatelessWidget {
  const _ListExamples();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        AppListItem(
          title: 'Promotor A',
          subtitle: 'Achievement 82% bulan ini',
          trailing: AppBadge(
            label: 'On Track',
            variant: AppBadgeVariant.success,
          ),
        ),
        SizedBox(height: AppSpace.md),
        AppListItem(
          title: 'Store Visit',
          subtitle: '2 temuan harus difollow-up',
          trailing: AppBadge(label: 'Urgent', variant: AppBadgeVariant.warning),
        ),
        SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(
              child: AppMetricRow(label: 'Sell Out', value: 'Rp 18.400.000'),
            ),
            SizedBox(width: AppSpace.sm),
            Expanded(
              child: AppMetricRow(label: 'Unit', value: '36'),
            ),
          ],
        ),
        SizedBox(height: AppSpace.md),
        AppStatCard(
          label: 'Promotor Aktif',
          value: '24',
          icon: Icons.people_outline,
        ),
      ],
    );
  }
}

class _ActionExamples extends StatelessWidget {
  const _ActionExamples();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: AppSpace.md,
      mainAxisSpacing: AppSpace.md,
      childAspectRatio: 0.86,
      children: [
        AppActionTile(
          icon: Icons.storefront_outlined,
          label: 'Visiting',
          description: 'Pantau coverage visit toko',
          onTap: () {},
        ),
        AppActionTile(
          icon: Icons.analytics_outlined,
          label: 'AllBrand',
          description: 'Monitor performa area',
          onTap: () {},
        ),
        AppActionTile(
          icon: Icons.inventory_2_outlined,
          label: 'Sell In',
          description: 'Kelola finalisasi dan gudang',
          onTap: () {},
        ),
      ],
    );
  }
}

class _InputExamples extends StatelessWidget {
  const _InputExamples();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AppInput(label: 'Nama Toko', hintText: 'Masukkan nama toko'),
        SizedBox(height: AppSpace.md),
        AppInput(
          label: 'Catatan',
          hintText: 'Tulis catatan singkat',
          maxLines: 3,
        ),
        SizedBox(height: AppSpace.xl),
        AppEmptyState(
          title: 'Belum Ada Data',
          message: 'Gunakan komponen ini untuk state kosong yang konsisten.',
        ),
      ],
    );
  }
}
