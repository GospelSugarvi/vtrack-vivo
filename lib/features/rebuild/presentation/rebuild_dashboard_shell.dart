import 'package:flutter/material.dart';

import '../../../ui/foundation/app_colors.dart';
import '../../../ui/foundation/app_radius.dart';
import '../../../ui/foundation/app_spacing.dart';

class RebuildDashboardShell extends StatelessWidget {
  const RebuildDashboardShell({
    super.key,
    required this.title,
    required this.currentIndex,
    required this.onTap,
    required this.body,
  });

  final String title;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Widget body;

  static const List<_ShellItem> _items = <_ShellItem>[
    _ShellItem('Home', Icons.home_outlined, Icons.home),
    _ShellItem('Workplace', Icons.work_outline, Icons.work),
    _ShellItem('Ranking', Icons.leaderboard_outlined, Icons.leaderboard),
    _ShellItem('Chat', Icons.chat_bubble_outline, Icons.chat_bubble),
    _ShellItem('Profil', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
      ),
      body: body,
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.infoSurface,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 22,
              color: selected ? AppColors.primaryStrong : AppColors.textSecondary,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onTap,
          destinations: _items
              .map(
                (item) => NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.activeIcon),
                  label: item.label,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class RebuildRoleHomePage extends StatefulWidget {
  const RebuildRoleHomePage({
    super.key,
    required this.config,
  });

  final RebuildRoleHomeConfig config;

  @override
  State<RebuildRoleHomePage> createState() => _RebuildRoleHomePageState();
}

class _RebuildRoleHomePageState extends State<RebuildRoleHomePage> {
  int _periodIndex = 0;
  int _navIndex = 0;

  static const List<String> _periods = <String>[
    'Harian',
    'Mingguan',
    'Bulanan',
  ];

  @override
  Widget build(BuildContext context) {
    return RebuildDashboardShell(
      title: widget.config.roleName,
      currentIndex: _navIndex,
      onTap: (index) => setState(() => _navIndex = index),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HomeHeader(
                greeting: 'Selamat datang,',
                userName: widget.config.userName,
                primaryChip: widget.config.primaryChip,
                secondaryInfo: widget.config.secondaryInfo,
                selectedPeriodIndex: _periodIndex,
                onPeriodChanged: (index) => setState(() => _periodIndex = index),
                periods: _periods,
              ),
              const SizedBox(height: AppSpace.lg),
              ...widget.config.sections.map(
                (section) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: _SectionCard(section: section),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RebuildRoleHomeConfig {
  const RebuildRoleHomeConfig({
    required this.roleName,
    required this.userName,
    required this.primaryChip,
    required this.secondaryInfo,
    required this.sections,
  });

  final String roleName;
  final String userName;
  final String primaryChip;
  final String secondaryInfo;
  final List<RebuildHomeSection> sections;
}

class RebuildHomeSection {
  const RebuildHomeSection({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<String> items;
}

class _ShellItem {
  const _ShellItem(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.greeting,
    required this.userName,
    required this.primaryChip,
    required this.secondaryInfo,
    required this.selectedPeriodIndex,
    required this.onPeriodChanged,
    required this.periods,
  });

  final String greeting;
  final String userName;
  final String primaryChip;
  final String secondaryInfo;
  final int selectedPeriodIndex;
  final ValueChanged<int> onPeriodChanged;
  final List<String> periods;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgBorder,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            userName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 24),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              _PillChip(label: primaryChip, backgroundColor: AppColors.infoSurface, foregroundColor: AppColors.primaryStrong),
              _PillChip(label: secondaryInfo, backgroundColor: AppColors.surfaceVariant, foregroundColor: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          _PeriodSwitcher(
            periods: periods,
            selectedIndex: selectedPeriodIndex,
            onChanged: onPeriodChanged,
          ),
        ],
      ),
    );
  }
}

class _PeriodSwitcher extends StatelessWidget {
  const _PeriodSwitcher({
    required this.periods,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> periods;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.pillBorder,
      ),
      child: Row(
        children: List<Widget>.generate(periods.length, (index) {
          final selected = index == selectedIndex;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == periods.length - 1 ? 0 : AppSpace.xs),
              child: InkWell(
                borderRadius: AppRadius.pillBorder,
                onTap: () => onChanged(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.surface : Colors.transparent,
                    borderRadius: AppRadius.pillBorder,
                    border: selected ? Border.all(color: AppColors.border) : null,
                  ),
                  child: Text(
                    periods[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.pillBorder,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final RebuildHomeSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgBorder,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            section.subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpace.md),
          ...section.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 8, color: AppColors.primary),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      item,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
