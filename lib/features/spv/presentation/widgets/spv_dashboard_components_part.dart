part of '../spv_dashboard.dart';

extension _SpvDashboardComponentsPart on _SpvDashboardState {
  Widget _buildSectionHead(String title, [String? note]) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: _gold,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: _goldGlow, blurRadius: 6, spreadRadius: 1),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Container(width: 8, height: 1.5, color: _gold),
              const SizedBox(width: 6),
              Text(
                title,
                style: _outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: _cream2,
                ),
              ),
            ],
          ),
          if (note != null && note.trim().isNotEmpty) ...[
            const Spacer(),
            Text(note, style: _outfit(size: 11, color: _muted)),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _s2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _s3),
      ),
      child: Text(
        label,
        style: _outfit(size: 7, weight: FontWeight.w700, color: _cream2),
      ),
    );
  }

  Widget _buildFocusProductRow(Map<String, dynamic> product) {
    final tags = <Widget>[
      if (_isTruthy(product['is_detail_target'])) _buildFocusChip('Detail'),
      if (_isTruthy(product['is_special'])) _buildFocusChip('Khusus'),
    ];
    final actualUnits = _toInt(product['actual_units']);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _goldDim,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.flag_rounded, size: 12, color: _gold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${product['model_name'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _outfit(
                    size: 11,
                    weight: FontWeight.w800,
                    color: _cream,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${product['series'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _outfit(size: 8, color: _muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: _goldDim,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _goldGlow),
            ),
            child: Text(
              '${actualUnits}u',
              style: _outfit(size: 8, weight: FontWeight.w800, color: _gold),
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final tag in tags)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: tag,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusInsightBlock({
    required int target,
    required int actual,
    required String title,
    required List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> specialRows = const <Map<String, dynamic>>[],
    bool embedded = false,
  }) {
    final remaining = math.max(0, target - actual);
    final progress = target > 0 ? (actual * 100 / target) : 0.0;

    return Container(
      margin: embedded
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: embedded
          ? const EdgeInsets.only(top: 12)
          : const EdgeInsets.all(14),
      decoration: embedded
          ? null
          : BoxDecoration(
              color: _s1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _s3),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = math.max(
            0.0,
            math.min(88.0, (constraints.maxWidth - 24) / 3),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildHeroBadge(title)),
                  const SizedBox(width: 10),
                  Text(
                    '${progress.toStringAsFixed(0)}%',
                    style: _display(
                      size: 15,
                      weight: FontWeight.w800,
                      color: _gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    SizedBox(
                      width: tileWidth,
                      child: _buildFocusSummaryTile(
                        label: 'Target',
                        value: '$target',
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _buildFocusSummaryTile(
                        label: 'Terjual',
                        value: '$actual',
                        valueColor: _green,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _buildFocusSummaryTile(
                        label: 'Sisa',
                        value: '$remaining',
                        valueColor: _amber,
                      ),
                    ),
                  ],
                ),
              ),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...rows.take(3).map(_buildFocusProductRow),
              ],
              if (specialRows.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildSpecialInsightCard(rows: specialRows),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSpecialInsightCard({
    required List<Map<String, dynamic>> rows,
    String title = 'Tipe Khusus',
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: _goldDim,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _goldGlow.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: _gold),
              const SizedBox(width: 6),
              Text(
                title,
                style: _outfit(size: 11, weight: FontWeight.w800, color: _gold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...rows.asMap().entries.map(
            (entry) => _buildSpecialBundleRow(
              detail: entry.value,
              index: entry.key + 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialBundleRow({
    required Map<String, dynamic> detail,
    required int index,
  }) {
    final bundleName = '${detail['bundle_name'] ?? 'Tipe Khusus'}';
    final targetQty = _toDouble(detail['target_qty']);
    final actualQty = _toDouble(detail['actual_qty']);
    final pct = _toDouble(detail['pct']);
    final tone = pct >= 100 ? _green : (pct >= 70 ? _gold : _red);

    String fmt(double value) => value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$index',
              style: _outfit(size: 10, weight: FontWeight.w800, color: tone),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              bundleName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _outfit(size: 12, weight: FontWeight.w700, color: _cream),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${fmt(actualQty)}/${fmt(targetQty)}',
            style: _outfit(size: 11, weight: FontWeight.w700, color: _cream2),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '${pct.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: _outfit(size: 11, weight: FontWeight.w800, color: tone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklySelectorCard() {
    if (_weeklySnapshots.isEmpty) return const SizedBox.shrink();
    final selectedSnapshot = _selectedWeeklySnapshot();
    final rangeLabel = _formatWeekRange(
      _parseDate(selectedSnapshot?['start_date']),
      _parseDate(selectedSnapshot?['end_date']),
    );
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: isLightMode ? Color.lerp(_s1, _gold, 0.03) : _s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isLightMode ? Color.lerp(_s3, _gold, 0.12) ?? _s3 : _s3,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = math.max(0.0, (constraints.maxWidth - 24) / 4);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Pilih Minggu',
                    style: _outfit(
                      size: 11,
                      weight: FontWeight.w800,
                      color: _cream,
                    ),
                  ),
                  const Spacer(),
                  Text(rangeLabel, style: _outfit(size: 8, color: _muted)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List<Widget>.generate(_weeklySnapshots.length, (
                  index,
                ) {
                  final snapshot = _weeklySnapshots[index];
                  final weekKey = _weeklySnapshotKey(snapshot);
                  final isSelected = weekKey == _selectedWeeklyKey;
                  final isActive = snapshot['is_active'] == true;
                  final isFuture = snapshot['is_future'] == true;
                  final weekNumber = _toInt(snapshot['week_number']);
                  final chipTone = isSelected
                      ? _gold
                      : isActive
                      ? _amber
                      : _cream2;

                  return SizedBox(
                    width: itemWidth,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () =>
                          _updateState(() => _selectedWeeklyKey = weekKey),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        decoration: ShapeDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isSelected
                                ? [
                                    _goldDim,
                                    isLightMode
                                        ? Color.lerp(
                                                _goldDim,
                                                Colors.white,
                                                0.22,
                                              ) ??
                                              _goldDim
                                        : _goldDim,
                                  ]
                                : [
                                    isLightMode
                                        ? Color.lerp(_s2, Colors.white, 0.24) ??
                                              _s2
                                        : _s2,
                                    _s2,
                                  ],
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isSelected
                                  ? _goldGlow
                                  : isActive
                                  ? _amber.withValues(alpha: 0.35)
                                  : _s3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Minggu $weekNumber',
                                    style: _outfit(
                                      size: 8,
                                      weight: FontWeight.w800,
                                      color: chipTone,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: chipTone,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _formatWeekRange(
                                _parseDate(snapshot['start_date']),
                                _parseDate(snapshot['end_date']),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _outfit(size: 8, color: _muted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isFuture
                                  ? 'Belum jalan'
                                  : '${snapshot['status_label'] ?? 'Riwayat'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _outfit(
                                size: 8,
                                weight: FontWeight.w700,
                                color: _cream2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSatorPanel(
    Map<String, dynamic> data, {
    required bool isWeekly,
    bool isMonthly = false,
  }) {
    final targetSellOut = isMonthly
        ? _toInt(data['target_sell_out_monthly'])
        : isWeekly
        ? _toInt(data['target_sell_out_weekly'])
        : _toInt(data['target_sell_out_daily']);
    final actualSellOut = isMonthly
        ? _toInt(data['actual_sell_out_monthly'])
        : isWeekly
        ? _toInt(data['actual_sell_out_weekly'])
        : _toInt(data['actual_sell_out_daily']);
    final targetFocus = isMonthly
        ? _toInt(data['target_focus_monthly'])
        : isWeekly
        ? _toInt(data['target_focus_weekly'])
        : _toInt(data['target_focus_daily']);
    final actualFocus = isMonthly
        ? _toInt(data['actual_focus_monthly'])
        : isWeekly
        ? _toInt(data['actual_focus_weekly'])
        : _toInt(data['actual_focus_daily']);
    final targetSellIn = isMonthly
        ? _toInt(data['target_sell_in_monthly'])
        : isWeekly
        ? _toInt(data['target_sell_in_weekly'])
        : _toInt(data['target_sell_in_daily']);
    final actualSellIn = isMonthly
        ? _toInt(data['actual_sell_in_monthly'])
        : isWeekly
        ? _toInt(data['actual_sell_in_weekly'])
        : _toInt(data['actual_sell_in_daily']);
    final pct = targetSellOut > 0 ? (actualSellOut * 100 / targetSellOut) : 0.0;
    final focusPct = targetFocus > 0 ? (actualFocus * 100 / targetFocus) : 0.0;
    final sellInPct = targetSellIn > 0
        ? (actualSellIn * 100 / targetSellIn)
        : 0.0;
    final isWarn = pct < 60;
    final color = isWarn ? _red : (pct < 80 ? _amber : _green);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _s2,
                  border: Border.all(color: _s3),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  data['sator_name'].toString().substring(0, 1),
                  style: _display(
                    size: 12,
                    weight: FontWeight.w800,
                    color: _cream2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['sator_name'],
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: _outfit(
                        size: 10,
                        weight: FontWeight.w700,
                        color: _cream,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${data['sator_area']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _outfit(size: 6, color: _muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${pct.toStringAsFixed(0)}%',
                    style: _display(
                      size: 15,
                      weight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildSatorMetricStack(
          topLabel: 'All Type',
          topPct: pct / 100,
          topColor: color,
          topValue:
              '${_currency.format(actualSellOut).replaceAll(',00', '')} / ${_currency.format(targetSellOut).replaceAll(',00', '')}',
          middleLabel: 'Produk Fokus',
          middlePct: focusPct / 100,
          middleColor: _amber,
          middleValue: '$actualFocus / $targetFocus',
          bottomLabel: 'Sell In',
          bottomPct: (sellInPct / 100).clamp(0, 1),
          bottomColor: _green,
          bottomValue:
              '${_currency.format(actualSellIn).replaceAll(',00', '')} / ${_currency.format(targetSellIn).replaceAll(',00', '')}',
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildSatorCardGrid(
    List<Map<String, dynamic>> rows, {
    required bool isWeekly,
    bool isMonthly = false,
  }) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var index = 0; index < rows.length; index += 2) {
      final left = rows[index];
      final right = index + 1 < rows.length ? rows[index + 1] : null;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: IntrinsicHeight(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: _s1,
                  border: Border.all(color: _s3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _buildSatorPanel(
                          left,
                          isWeekly: isWeekly,
                          isMonthly: isMonthly,
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      color: _s3,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: right != null
                            ? _buildSatorPanel(
                                right,
                                isWeekly: isWeekly,
                                isMonthly: isMonthly,
                              )
                            : Container(color: _s1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Column(children: children);
  }

  Widget _buildSatorMetricStack({
    required String topLabel,
    required double topPct,
    required Color topColor,
    required String topValue,
    required String middleLabel,
    required double middlePct,
    required Color middleColor,
    required String middleValue,
    required String bottomLabel,
    required double bottomPct,
    required Color bottomColor,
    required String bottomValue,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.surface2)),
      ),
      child: Column(
        children: [
          _buildSatorMetricCell(
            label: topLabel,
            pct: topPct,
            color: topColor,
            value: topValue,
            emphasizeValue: true,
            showPercentage: false,
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            height: 1,
            color: _s3,
          ),
          _buildSatorMetricCell(
            label: middleLabel,
            pct: middlePct,
            color: middleColor,
            value: middleValue,
            showPercentage: false,
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            height: 1,
            color: _s3,
          ),
          _buildSatorMetricCell(
            label: bottomLabel,
            pct: bottomPct,
            color: bottomColor,
            value: bottomValue,
            showPercentage: false,
          ),
        ],
      ),
    );
  }

  Widget _buildSatorMetricCell({
    required String label,
    required double pct,
    required Color color,
    required String value,
    bool emphasizeValue = false,
    bool showPercentage = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label, style: _outfit(size: 11, color: _muted)),
            ),
            if (showPercentage) ...[
              const SizedBox(width: 8),
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: _outfit(size: 13, weight: FontWeight.w800, color: color),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.topLeft,
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: emphasizeValue
                ? _display(size: 11, weight: FontWeight.w800, color: _cream2)
                : _outfit(size: 10, weight: FontWeight.w800, color: _cream2),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: _s3,
            borderRadius: BorderRadius.circular(100),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: pct.clamp(0, 1),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _goldDim,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _goldGlow),
      ),
      child: Text(
        label,
        style: _outfit(size: 10, weight: FontWeight.w800, color: _gold),
      ),
    );
  }

  Widget _buildHeroMetaCard({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: _s1.withValues(
          alpha: Theme.of(context).brightness == Brightness.light ? 0.72 : 0.18,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _outfit(size: 7, color: _muted)),
          const SizedBox(height: 2),
          SizedBox(
            height: 16,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: _display(
                  size: 11,
                  weight: FontWeight.w800,
                  color: valueColor ?? _cream,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusSummaryTile({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _s1.withValues(
          alpha: Theme.of(context).brightness == Brightness.light ? 0.72 : 0.18,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _outfit(size: 7, color: _muted)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _outfit(
              size: 10,
              weight: FontWeight.w800,
              color: valueColor ?? _cream,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard({
    required String label,
    required int nominal,
    required String actualLabel,
    required int actualVal,
    required double pct,
    required String pctLabel,
    required String progressLabel,
    required String progressNote,
    required List<String> chips,
    Widget? bottomContent,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        final ringTone = pct < 0.6 ? _red : (pct < 0.8 ? _amber : _gold);
        final ringLabel = pctLabel.trim().isEmpty
            ? '-'
            : pctLabel.trim().split(RegExp(r'\s+')).first;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_heroStart, _heroEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: _goldGlow),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _gold.withValues(alpha: 0),
                      _gold.withValues(alpha: 0.6),
                      _gold.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeroBadge(label),
                              const SizedBox(height: 4),
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Rp ',
                                      style: _outfit(
                                        size: 9,
                                        weight: FontWeight.w800,
                                        color: _cream2,
                                      ),
                                    ),
                                    TextSpan(
                                      text: _currency
                                          .format(nominal)
                                          .replaceAll('Rp ', ''),
                                      style: _display(
                                        size: narrow ? 17 : 18,
                                        weight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: narrow ? 44 : 46,
                          height: narrow ? 44 : 46,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: narrow ? 44 : 46,
                                height: narrow ? 44 : 46,
                                child: CircularProgressIndicator(
                                  value: pct.clamp(0, 1),
                                  strokeWidth: 3.8,
                                  backgroundColor: _s3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    ringTone,
                                  ),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${(pct * 100).toStringAsFixed(0)}%',
                                    style: _display(
                                      size: 9,
                                      weight: FontWeight.w800,
                                      color: ringTone,
                                    ),
                                  ),
                                  Text(
                                    ringLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _outfit(size: 6, color: _cream2),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildHeroMetaCard(
                            label: actualLabel,
                            value: _currency
                                .format(actualVal)
                                .replaceAll(',00', ''),
                            valueColor: _green,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildHeroMetaCard(
                            label: progressLabel,
                            value: progressNote,
                            valueColor: _goldLt,
                          ),
                        ),
                      ],
                    ),
                    if (bottomContent case final Widget content) content,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroStripItem(String label, String val, {Color? valColor}) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: _s1.withValues(
            alpha: Theme.of(context).brightness == Brightness.light
                ? 0.72
                : 0.18,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _s3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _outfit(
                size: 7,
                weight: FontWeight.w700,
                color: _muted,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 16,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  val,
                  maxLines: 1,
                  style: _display(
                    size: 11,
                    weight: FontWeight.w800,
                    color: valColor ?? _cream,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompareCard() {
    if (_satorTargetBreakdown.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: _s1,
        border: Border.all(color: _s3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _s3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'KPI Bulanan per Area',
                  style: _outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: _cream2,
                  ),
                ),
                Text('Target: 100%', style: _outfit(size: 8, color: _muted)),
              ],
            ),
          ),
          Row(
            children: [
              Builder(
                builder: (context) {
                  return _buildCompareArea(
                    _satorTargetBreakdown[0]['sator_name'],
                    _toInt(_satorTargetBreakdown[0]['achievement_pct_monthly']),
                    _red,
                  );
                },
              ),
              Container(width: 1, height: 60, color: _s3),
              if (_satorTargetBreakdown.length > 1)
                Builder(
                  builder: (context) {
                    return _buildCompareArea(
                      _satorTargetBreakdown[1]['sator_name'],
                      _toInt(
                        _satorTargetBreakdown[1]['achievement_pct_monthly'],
                      ),
                      _amber,
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpvKpiCompactCard() {
    final kpi = _spvKpiSummary ?? const <String, dynamic>{};
    final totalScore = _toDouble(kpi['total_score']);
    final totalBonus = _toInt(kpi['total_bonus']);

    Widget metric(String label, String value, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: _s2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _s3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _outfit(size: 8, color: _muted)),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _outfit(size: 10, weight: FontWeight.w800, color: color),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => context.pushNamed('spv-kpi-monitor'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _s3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'KPI Bulanan SPV',
                    style: _outfit(size: 12, weight: FontWeight.w800),
                  ),
                ),
                Text(
                  totalScore.toStringAsFixed(2),
                  style: _outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: _gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: metric(
                    'Sell Out',
                    _toDouble(kpi['sell_out_all_score']).toStringAsFixed(2),
                    _gold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: metric(
                    'Produk Fokus',
                    _toDouble(kpi['sell_out_fokus_score']).toStringAsFixed(2),
                    _amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: metric(
                    'Sell In',
                    _toDouble(kpi['sell_in_score']).toStringAsFixed(2),
                    _green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: metric(
                    'KPI MA',
                    _toDouble(kpi['kpi_ma_score']).toStringAsFixed(2),
                    _cream2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            metric(
              'Estimasi Bonus',
              _currency.format(totalBonus).replaceAll(',00', ''),
              _green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompareArea(String name, int pct, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text(
              name.toUpperCase(),
              style: _outfit(
                size: 8,
                weight: FontWeight.w700,
                color: _muted,
                letterSpacing: 0.64,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$pct%',
              style: _display(size: 26, weight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 4),
            Container(
              width: 80,
              height: 4,
              decoration: BoxDecoration(
                color: _s3,
                borderRadius: BorderRadius.circular(100),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (pct / 100).clamp(0, 1),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 22),
      decoration: BoxDecoration(
        color: _bottomBarBg,
        border: Border(top: BorderSide(color: _s3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.home_outlined, Icons.home, 'Home', 0),
          _buildNavItem(
            Icons.analytics_outlined,
            Icons.analytics,
            'Workplace',
            1,
          ),
          _buildNavItem(
            Icons.business_center_outlined,
            Icons.business_center,
            'Ranking',
            2,
          ),
          _buildNavItem(
            Icons.chat_bubble_outline,
            Icons.chat_bubble,
            'Chat',
            3,
            customIcon: AppUnreadBadgeIcon(
              unreadCount: _unreadCount,
              selected: _currentIndex == 3,
            ),
          ),
          _buildNavItem(Icons.person_outline, Icons.person, 'Profil', 4),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    IconData activeIcon,
    String label,
    int index, {
    Widget? customIcon,
  }) {
    final active = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        _updateState(() {
          _currentIndex = index;
          if (index >= 2) {
            _loadedTabSlots.add(index - 1);
          }
        });
        if (index == 1 && _permissionPendingCount == 0) {
          _loadPermissionPendingCount();
        }
        if (index == 3) {
          _loadUnreadCount();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? _goldDim : _goldDim.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(color: active ? _gold : _muted2, size: 18),
              child:
                  customIcon ??
                  Icon(
                    active ? activeIcon : icon,
                    color: active ? _gold : _muted2,
                    size: 18,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: _outfit(
                size: 11,
                weight: FontWeight.w700,
                color: active ? _gold : _muted2,
                letterSpacing: 0.32,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVastCompactCard() {
    final vast = _vastSnapshot;
    final target = _toInt(vast['target_submissions']);
    final input = _toInt(vast['total_submissions']);
    final reject = _toInt(vast['total_reject']);
    final pending = _toInt(vast['total_active_pending']);
    final closing =
        _toInt(vast['total_closed_direct']) +
        _toInt(vast['total_closed_follow_up']);
    final duplicateAlerts = _toInt(vast['total_duplicate_alerts']);
    final pct = target > 0
        ? ((input * 100) / target)
        : _toDouble(vast['achievement_pct']);
    final tone = pct >= 100 ? _green : (pct > 0 ? _amber : _muted);
    final progress = target > 0 ? (input / target).clamp(0, 1).toDouble() : 0.0;
    final targetLabel = _homeFrameIndex == 1
        ? 'Target Mingguan'
        : _homeFrameIndex == 2
        ? 'Target Bulanan'
        : 'Target Harian';

    Widget metric(String label, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            color: _s2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _outfit(size: 8, color: _muted)),
              const SizedBox(height: 2),
              Text(
                value,
                style: _outfit(size: 11, weight: FontWeight.w800, color: color),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => context.pushNamed('spv-vast'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _s3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _goldDim,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _goldGlow),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 12,
                    color: _gold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'VAST Finance',
                    style: _outfit(size: 12, weight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: _outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: tone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$targetLabel: $target input',
                    style: _outfit(size: 9, color: _cream2),
                  ),
                ),
                if (duplicateAlerts > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$duplicateAlerts alert',
                      style: _outfit(
                        size: 8,
                        weight: FontWeight.w700,
                        color: _red,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$input input • $_vastPeriodLabel',
              style: _outfit(size: 9, color: _muted),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: _s3,
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                metric('Input', '$input', _gold),
                const SizedBox(width: 8),
                metric('Reject', '$reject', _red),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                metric('Pending', '$pending', _amber),
                const SizedBox(width: 8),
                metric('Closing', '$closing', _green),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
