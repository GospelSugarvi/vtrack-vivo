part of '../spv_dashboard.dart';

extension _SpvDashboardLayoutPart on _SpvDashboardState {
  Widget _buildDateBadge(String label, {double fontSize = 11}) {
    return IntrinsicWidth(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: _s1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _s3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, size: 11, color: _gold),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: _outfit(size: fontSize, color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardBody() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(_t.radiusXl),
              ),
              boxShadow: [
                BoxShadow(
                  color: _bg,
                  blurRadius: 140,
                  offset: const Offset(0, 50),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(_t.radiusXl),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refreshAll,
                      color: _gold,
                      backgroundColor: _s1,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 100),
                        children: [
                          _buildHeader(),
                          _buildHeaderControls(),
                          _buildContentPanel(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 390;
        final veryCompact = width < 360;
        final headerHorizontal = veryCompact ? 10.0 : 12.0;
        final headerPadding = veryCompact
            ? const EdgeInsets.fromLTRB(10, 10, 10, 8)
            : compact
            ? const EdgeInsets.fromLTRB(12, 12, 12, 10)
            : const EdgeInsets.fromLTRB(14, 14, 14, 12);
        final avatarRadius = veryCompact
            ? 16.0
            : compact
            ? 18.0
            : 20.0;
        final avatarRing = veryCompact ? 1.0 : 1.5;
        final titleSize = veryCompact
            ? 18.0
            : compact
            ? 20.0
            : 22.0;
        final areaSize = veryCompact ? 10.0 : 11.0;
        final roleSize = veryCompact ? 9.0 : 10.0;
        final contentGap = veryCompact ? 8.0 : 10.0;
        final nameGap = veryCompact ? 3.0 : 5.0;

        return Container(
          margin: EdgeInsets.fromLTRB(headerHorizontal, 6, headerHorizontal, 4),
          padding: headerPadding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark ? [_s1, _s2] : [_s1, _bg],
            ),
            borderRadius: BorderRadius.circular(veryCompact ? 16 : 20),
            border: Border.all(color: _s3),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? _bg.withValues(alpha: 0.16)
                    : const Color(0xFF000000).withValues(alpha: 0.04),
                blurRadius: veryCompact ? 14 : 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_currentIndex == 1)
                    Expanded(
                      child: Text(
                        'Workplace',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _display(size: compact ? 18 : 20, color: _cream),
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        'Home',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _display(size: compact ? 18 : 20, color: _cream),
                      ),
                    ),
                  AppNotificationBellButton(
                    backgroundColor: _s1,
                    borderColor: _s3,
                    iconColor: _muted,
                    badgeColor: _red,
                    badgeTextColor: _bg,
                    routePath: '/spv/notifications',
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => context.push('/spv/home-search'),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _s1,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _s3),
                      ),
                      child: Icon(
                        Icons.search_rounded,
                        color: _muted,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(avatarRing),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _goldGlow),
                    ),
                    child: _headerAvatarReady
                        ? UserAvatar(
                            key: ValueKey(_spvAvatarUrl),
                            avatarUrl: _spvAvatarUrl.isEmpty
                                ? null
                                : _spvAvatarUrl,
                            fullName: _spvName,
                            radius: avatarRadius,
                            showBorder: false,
                          )
                        : Container(
                            width: avatarRadius * 2,
                            height: avatarRadius * 2,
                            decoration: BoxDecoration(
                              color: _s2,
                              shape: BoxShape.circle,
                            ),
                          ),
                  ),
                  SizedBox(width: contentGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_headerIdentityReady) ...[
                          Text(
                            _spvName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _display(
                              size: compact ? titleSize - 1 : titleSize,
                              weight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: nameGap),
                          Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            children: [
                              Text(
                                _spvArea.isNotEmpty && _spvArea != '-'
                                    ? _spvArea
                                    : 'Area: -',
                                style: _outfit(
                                  size: areaSize,
                                  weight: FontWeight.w700,
                                  color: _gold,
                                ),
                              ),
                              Text(
                                'Role: ${_spvRole.toUpperCase()}',
                                style: _outfit(
                                  size: roleSize,
                                  weight: FontWeight.w700,
                                  color: _cream2,
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Container(
                            height: compact ? 18 : 20,
                            width: veryCompact ? 132 : 168,
                            decoration: BoxDecoration(
                              color: _s2,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          SizedBox(height: nameGap),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Container(
                                height: compact ? 10 : 11,
                                width: 76,
                                decoration: BoxDecoration(
                                  color: _s2,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              Container(
                                height: compact ? 10 : 11,
                                width: 84,
                                decoration: BoxDecoration(
                                  color: _s2,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderControls() {
    final dateLabel = DateFormat(
      'EEEE, d MMM yyyy',
      'id_ID',
    ).format(DateTime.now());
    if (_currentIndex == 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _buildDateBadge(dateLabel),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dateLabel = DateFormat(
            constraints.maxWidth < 360
                ? 'd MMM yyyy'
                : constraints.maxWidth < 430
                ? 'EEE, d MMM'
                : 'EEEE, d MMM yyyy',
            'id_ID',
          ).format(DateTime.now());
          final segmented = ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth < 360 ? 184 : 212,
            ),
            child: FieldSegmentedControl(
              labels: const ['Harian', 'Mingguan', 'Bulanan'],
              selectedIndex: _homeFrameIndex,
              onSelected: (index) async {
                _updateState(() => _homeFrameIndex = index);
                if (index == 1 && !_weeklySnapshotReady) {
                  await _loadWeeklySnapshots();
                }
              },
            ),
          );

          return Row(
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _buildDateBadge(
                      dateLabel,
                      fontSize: constraints.maxWidth < 360 ? 8.5 : 9.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Spacer(),
              segmented,
            ],
          );
        },
      ),
    );
  }

  Widget _buildContentPanel() {
    if (!_homeSnapshotReady) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: _s1,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _s3),
          ),
          alignment: Alignment.center,
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(_gold),
              backgroundColor: _s3,
            ),
          ),
        ),
      );
    }
    if (_currentIndex == 1) return _buildWorkplacePanel();
    return _buildTabPanel();
  }

  Widget _buildTabPanel() {
    if (_homeFrameIndex == 0) return _buildHarianTab();
    if (_homeFrameIndex == 1) return _buildMingguanTab();
    return _buildBulananTab();
  }

  Widget _buildWorkplacePanel() {
    final submitted = _toInt(_scheduleSummary?['submitted']);
    final aktivitasBadge = '${_satorTargetBreakdown.length} SATOR';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWorkplaceSection(
            title: 'Perlu Dicek Hari Ini',
            items: [
              _buildWorkplaceItem(
                title: 'Monitor Sell Out',
                icon: Icons.point_of_sale_rounded,
                badge: 'Hari ini',
                onTap: () => context.pushNamed('spv-sellout-monitor'),
              ),
              _buildWorkplaceItem(
                title: 'VAST Finance',
                icon: Icons.account_balance_wallet_outlined,
                badge: 'Monitor',
                onTap: () => context.pushNamed('spv-vast'),
              ),
              _buildWorkplaceItem(
                title: 'Visiting Monitoring',
                icon: Icons.store_mall_directory_rounded,
                badge: 'Harian',
                onTap: () => context.pushNamed('spv-visiting-monitor'),
              ),
              _buildWorkplaceItem(
                title: 'Approval Perijinan',
                icon: Icons.assignment_turned_in_outlined,
                badge: _permissionPendingCount > 0
                    ? '$_permissionPendingCount pending'
                    : 'Siap',
                onTap: () => context.pushNamed('spv-permission-approval'),
              ),
            ],
          ),
          _buildWorkplaceSection(
            title: 'Monitoring Tim',
            items: [
              _buildWorkplaceCompactItem(
                title: 'Aktivitas Tim',
                icon: Icons.groups_rounded,
                badge: aktivitasBadge,
                onTap: () => context.pushNamed('spv-aktivitas-tim'),
              ),
              _buildWorkplaceCompactItem(
                title: 'Monitor Sell-In',
                icon: Icons.trending_up_rounded,
                badge: 'Hari ini',
                onTap: () => context.pushNamed('spv-sellin-monitor'),
              ),
              _buildWorkplaceCompactItem(
                title: 'Monitor Stok Toko',
                icon: Icons.sim_card_outlined,
                badge: 'Area',
                onTap: () => context.pushNamed('spv-stock-management'),
              ),
            ],
          ),
          _buildWorkplaceSection(
            title: 'Laporan & Evaluasi',
            items: [
              _buildWorkplaceCompactItem(
                title: 'Monitor All Brand',
                icon: Icons.analytics_rounded,
                badge: 'Harian',
                onTap: () => context.pushNamed('spv-allbrand'),
              ),
              _buildWorkplaceCompactItem(
                title: 'KPI Monitoring',
                icon: Icons.query_stats_rounded,
                badge: 'Bulanan',
                onTap: () => context.pushNamed('spv-kpi-monitor'),
              ),
              _buildWorkplaceCompactItem(
                title: 'Data Konsumen',
                icon: Icons.people_alt_outlined,
                badge: 'Riwayat',
                onTap: () => context.pushNamed('spv-customer-data'),
              ),
            ],
          ),
          _buildWorkplaceSection(
            title: 'Periodik',
            items: [
              _buildWorkplaceItem(
                title: 'Monitor Jadwal Bulanan',
                icon: Icons.calendar_month_rounded,
                badge: submitted > 0 ? '$submitted pending' : 'Bulanan',
                onTap: () => context.pushNamed('spv-jadwal-monitor'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkplaceSection({
    required String title,
    required List<Widget> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              title,
              style: _outfit(
                size: 11,
                weight: FontWeight.w800,
                color: _muted2,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _s1,
              borderRadius: BorderRadius.circular(_t.radiusLg),
              border: Border.all(color: _s3),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  items[i],
                  if (i < items.length - 1)
                    Divider(
                      height: 1,
                      color: _s3,
                      indent: 14,
                      endIndent: 14,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkplaceItem({
    required String title,
    required IconData icon,
    String? subtitle,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_t.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _goldDim,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _gold, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _outfit(size: 12, weight: FontWeight.w700),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: _outfit(size: 10, color: _muted)),
                    ],
                  ],
                ),
              ),
              if (badge != null) ...[
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _goldDim,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _goldGlow),
                  ),
                  child: Text(
                    badge,
                    style: _outfit(
                      size: 9,
                      weight: FontWeight.w700,
                      color: _gold,
                    ),
                  ),
                ),
              ],
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: _gold,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkplaceCompactItem({
    required String title,
    required IconData icon,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_t.radiusLg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _goldDim,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: _gold, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _outfit(size: 11, weight: FontWeight.w800),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _goldDim,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _goldGlow),
                  ),
                  child: Text(
                    badge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _outfit(
                      size: 8.8,
                      weight: FontWeight.w700,
                      color: _gold,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: _gold,
                size: 13,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHarianTab() {
    final targetHarian = _toInt(_teamTargetData?['target_sell_out_daily']);
    final achievement = targetHarian > 0 ? (_todayOmzet / targetHarian) : 0.0;

    return Column(
      children: [
        GestureDetector(
          onTap: () => context.pushNamed(AppRouteNames.targetDetail),
          child: _buildHeroCard(
            label: 'Target Harian',
            nominal: targetHarian,
            actualLabel: 'Pencapaian',
            actualVal: _todayOmzet,
            pct: achievement,
            pctLabel: 'harian',
            progressLabel: 'Progress',
            progressNote:
                'Sisa ${_currency.format(math.max(0, targetHarian - _todayOmzet)).replaceAll(',00', '')}',
            chips: const <String>[],
            bottomContent: _buildDailyFocusContent(),
          ),
        ),
        const SizedBox(height: 4),
        _buildSectionHead('VAST Finance', 'hari ini'),
        _buildVastCompactCard(),
        _buildSectionHead('Target Harian Sator'),
        _buildSatorCardGrid(_satorTargetBreakdown, isWeekly: false),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDailyFocusContent() {
    final focusTarget = _toInt(_teamTargetData?['target_focus_daily']);
    final focusActual = _satorTargetBreakdown.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['actual_focus_daily']),
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _s3)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: _buildFocusInsightBlock(
        target: focusTarget,
        actual: focusActual,
        title: 'Produk Fokus',
        rows: _activeFocusRows,
        specialRows: _activeSpecialRows,
        embedded: true,
      ),
    );
  }

  Widget _buildMingguanTab() {
    if (!_weeklySnapshotReady) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: _s1,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _s3),
          ),
          alignment: Alignment.center,
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(_gold),
              backgroundColor: _s3,
            ),
          ),
        ),
      );
    }

    final selectedSnapshot = _selectedWeeklySnapshot();
    final summary = Map<String, dynamic>.from(
      selectedSnapshot?['summary'] ?? const <String, dynamic>{},
    );
    final weekNum = _toInt(
      selectedSnapshot?['week_number'] ??
          _teamTargetData?['active_week_number'],
    );
    final workingDays = _toInt(
      selectedSnapshot?['working_days'] ?? _teamTargetData?['working_days'],
    );
    final elapsedWorkingDays = _toInt(
      selectedSnapshot?['elapsed_working_days'],
    );
    final targetW = _toInt(
      summary['target_sell_out_weekly'] ??
          _teamTargetData?['target_sell_out_weekly'],
    );
    final actualW = _toInt(summary['actual_sell_out_weekly'] ?? _weekOmzet);
    final achievement = targetW > 0 ? (actualW / targetW) : 0.0;
    final focusTarget = _toInt(
      summary['target_focus_weekly'] ?? _teamTargetData?['target_focus_weekly'],
    );
    final focusActual = _toInt(
      summary['actual_focus_weekly'] ?? _weekFocusUnits,
    );
    final satorRows = List<Map<String, dynamic>>.from(
      (selectedSnapshot?['sator_cards'] as List? ?? _satorTargetBreakdown).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final rangeLabel = _formatWeekRange(
      _parseDate(selectedSnapshot?['start_date']),
      _parseDate(selectedSnapshot?['end_date']),
    );
    final statusLabel = '${selectedSnapshot?['status_label'] ?? 'Aktif'}';

    return Column(
      children: [
        _buildHeroCard(
          label: 'Target Mingguan',
          nominal: targetW,
          actualLabel: 'Realisasi',
          actualVal: actualW,
          pct: achievement,
          pctLabel: statusLabel,
          progressLabel: weekNum > 0
              ? 'Minggu ke-$weekNum · $rangeLabel'
              : rangeLabel,
          progressNote:
              '$elapsedWorkingDays/$workingDays hari kerja · Sisa ${_currency.format(math.max(0, targetW - actualW))}',
          chips: _spvArea
              .split(RegExp(r'[,·]'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .take(2)
              .toList(),
          bottomContent: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: _s3)),
                ),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: _buildFocusInsightBlock(
                  target: focusTarget,
                  actual: focusActual,
                  title: 'Produk Fokus',
                  rows: _activeFocusRows,
                  specialRows: _activeSpecialRows,
                  embedded: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildWeeklySelectorCard(),
        const SizedBox(height: 4),
        _buildSectionHead(
          'VAST Finance',
          weekNum > 0 ? 'Minggu $weekNum' : 'Mingguan',
        ),
        _buildVastCompactCard(),
        _buildSectionHead('Target Mingguan SATOR'),
        _buildSatorCardGrid(satorRows, isWeekly: true),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildBulananTab() {
    final now = DateTime.now();
    final daysInMonth = math.max(
      1,
      DateUtils.getDaysInMonth(now.year, now.month),
    );
    final targetM = _toInt(_teamTargetData?['target_sell_out_monthly']);
    final achievement = targetM > 0 ? (_monthOmzet / targetM) : 0.0;
    final focusTarget = _toInt(_teamTargetData?['target_focus_monthly']);
    final focusActual = _satorTargetBreakdown.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['actual_focus_monthly']),
    );

    return Column(
      children: [
        _buildHeroCard(
          label: 'Target Bulanan',
          nominal: targetM,
          actualLabel: 'Realisasi',
          actualVal: _monthOmzet,
          pct: achievement,
          pctLabel: 'Bulanan',
          progressLabel: 'Progress ${DateFormat('MMMM yyyy').format(now)}',
          progressNote:
              'Sisa ${_currency.format(math.max(0, targetM - _monthOmzet))}',
          chips: _spvArea
              .split(RegExp(r'[,·]'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .take(2)
              .toList(),
          bottomContent: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: _s3)),
                ),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: _buildFocusInsightBlock(
                  target: focusTarget,
                  actual: focusActual,
                  title: 'Produk Fokus',
                  rows: _activeFocusRows,
                  specialRows: _activeSpecialRows,
                  embedded: true,
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: _s3)),
                ),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Row(
                  children: [
                    _buildHeroStripItem(
                      'Hari Kerja',
                      '${now.day}/$daysInMonth',
                    ),
                    const SizedBox(width: 6),
                    _buildHeroStripItem(
                      'Target/Hari',
                      _currency
                          .format(
                            math.max(0, targetM - _monthOmzet) /
                                math.max(1, daysInMonth - now.day),
                          )
                          .replaceAll('Rp ', 'Rp')
                          .replaceAll(',00', ''),
                    ),
                    const SizedBox(width: 6),
                    _buildHeroStripItem('vs Feb', '↑ +4%', valColor: _green),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _buildSectionHead(
          'VAST Finance',
          DateFormat('MMMM yyyy', 'id_ID').format(now),
        ),
        _buildVastCompactCard(),
        _buildSectionHead('KPI SPV', 'bulanan'),
        _buildSpvKpiCompactCard(),
        _buildSectionHead('Perbandingan Area'),
        _buildCompareCard(),
        _buildSectionHead('Target Bulanan Sator'),
        _buildSatorCardGrid(
          _satorTargetBreakdown,
          isWeekly: false,
          isMonthly: true,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
