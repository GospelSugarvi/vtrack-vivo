import 'package:flutter/material.dart';

class AppSafeHeader extends StatelessWidget {
  const AppSafeHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 12),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        topInset + padding.top,
        padding.right,
        padding.bottom,
      ),
      child: child,
    );
  }
}
