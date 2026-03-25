import 'package:flutter/material.dart';

import '../foundation/app_spacing.dart';
import '../foundation/field_theme_extensions.dart';
import '../promotor/promotor_theme.dart';

class AppDashboardShell extends StatelessWidget {
  const AppDashboardShell({
    super.key,
    required this.body,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.overlay,
  });

  final Widget body;
  final int currentIndex;
  final List<BottomNavigationBarItem> items;
  final ValueChanged<int> onTap;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final children = <Widget>[Positioned.fill(child: body)];
    if (overlay != null) {
      children.add(overlay!);
    }

    return Scaffold(
      extendBody: false,
      body: Stack(children: children),
      backgroundColor: t.shellBackground,
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: t.surface1,
          surfaceTintColor: t.background.withValues(alpha: 0),
          indicatorColor: t.primaryAccent,
          height: 80,
          elevation: 0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? t.textOnAccent : t.textMutedStrong,
              size: 24,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: selected ? t.primaryAccent : t.textSecondary,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onTap,
          destinations: items
              .map(
                (item) => NavigationDestination(
                  icon: item.icon,
                  selectedIcon: item.activeIcon,
                  label: item.label ?? '',
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class AppUnreadBadgeIcon extends StatelessWidget {
  const AppUnreadBadgeIcon({
    super.key,
    required this.unreadCount,
    required this.selected,
  });

  final int unreadCount;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(selected ? Icons.chat_bubble : Icons.chat_bubble_outline),
        if (unreadCount > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.xs,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: t.danger,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Center(
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: t.textOnAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AppLoadingScaffold extends StatelessWidget {
  const AppLoadingScaffold({super.key, this.label = 'Memuat data...'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.shellBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.primaryAccent),
            const SizedBox(height: AppSpace.md),
            Text(
              label,
              style: PromotorText.outfit(
                size: 15,
                weight: FontWeight.w500,
                color: t.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
