import 'package:flutter/widgets.dart';

import 'app_spacing.dart';

final class AppLayout {
  static const double contentMaxWidth = 1160;
  static const double tabletBreakpoint = 720;
  static const double desktopBreakpoint = 1100;

  static const EdgeInsets pagePadding = EdgeInsets.all(AppSpace.md);
  static const EdgeInsets pagePaddingWide = EdgeInsets.symmetric(
    horizontal: AppSpace.xl,
    vertical: AppSpace.lg,
  );

  const AppLayout._();
}

class AppPageContainer extends StatelessWidget {
  const AppPageContainer({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final resolvedPadding = width >= AppLayout.tabletBreakpoint
        ? AppLayout.pagePaddingWide
        : AppLayout.pagePadding;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.contentMaxWidth),
        child: Padding(padding: padding ?? resolvedPadding, child: child),
      ),
    );
  }
}
