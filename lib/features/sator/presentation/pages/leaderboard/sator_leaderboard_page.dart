import 'package:flutter/material.dart';

import '../../../../promotor/presentation/pages/leaderboard_page.dart';

class SatorLeaderboardPage extends StatelessWidget {
  const SatorLeaderboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LeaderboardPage(
      title: 'Ranking Tim',
      liveSubtitle: 'Live semua area · source ranking bersama',
      scopeLabel: 'Semua Area',
    );
  }
}
