import '../../../allbrand/presentation/pages/team_allbrand_monitor_page.dart';

class SpvAllbrandPage extends TeamAllbrandMonitorPage {
  const SpvAllbrandPage({super.key})
    : super(
        title: 'All Brand Area',
        rpcName: 'get_spv_allbrand_daily_monitor',
        principalParam: 'p_spv_id',
        showSatorName: true,
      );
}
