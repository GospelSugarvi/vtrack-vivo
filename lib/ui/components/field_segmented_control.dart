import 'package:flutter/material.dart';

import '../foundation/field_theme_extensions.dart';

class FieldSegmentedControl extends StatelessWidget {
  const FieldSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.fieldTokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedWidth = constraints.hasBoundedWidth;
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: tokens.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tokens.surface3),
          ),
          child: Row(
            mainAxisSize: hasBoundedWidth ? MainAxisSize.max : MainAxisSize.min,
            children: List.generate(labels.length, (index) {
              final active = selectedIndex == index;
              final segment = GestureDetector(
                onTap: () => onSelected(index),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: active ? tokens.primaryAccent : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[index],
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: active ? tokens.textOnAccent : tokens.textMuted,
                      ),
                    ),
                  ),
                ),
              );

              if (hasBoundedWidth) {
                return Expanded(child: segment);
              }

              return Flexible(fit: FlexFit.loose, child: segment);
            }),
          ),
        );
      },
    );
  }
}
