import 'package:flutter/material.dart';

typedef AdminReloadCallback = Future<void> Function();

Future<bool> showAdminChangedDialog({
  required BuildContext context,
  required WidgetBuilder builder,
  AdminReloadCallback? onChanged,
  bool barrierDismissible = true,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );

  if (changed == true && context.mounted && onChanged != null) {
    await onChanged();
  }

  return changed == true;
}

void closeAdminDialog(BuildContext context, {bool changed = false}) {
  Navigator.of(context).pop(changed);
}
