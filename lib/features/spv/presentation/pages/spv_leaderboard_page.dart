import 'package:flutter/material.dart';

import '../../../promotor/presentation/pages/leaderboard_page.dart';

class SpvLeaderboardPage extends StatelessWidget {
  const SpvLeaderboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LeaderboardPage(
      title: 'Ranking Area',
      liveSubtitle: 'Live semua area · source ranking bersama',
      scopeLabel: 'Semua Area',
    );
  }
}
