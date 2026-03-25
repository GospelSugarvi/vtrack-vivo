import 'package:flutter/material.dart';

import 'sell_in_order_composer_page.dart';

class RekomendasiPage extends StatefulWidget {
  final String? storeId;
  final String? groupId;

  const RekomendasiPage({super.key, this.storeId, this.groupId});

  @override
  State<RekomendasiPage> createState() => _RekomendasiPageState();
}

class _RekomendasiPageState extends State<RekomendasiPage> {
  @override
  Widget build(BuildContext context) {
    return SellInOrderComposerPage(
      mode: SellInOrderComposerMode.recommendation,
      storeId: widget.storeId,
      groupId: widget.groupId,
    );
  }
}
