import '../../../allbrand/presentation/pages/team_allbrand_monitor_page.dart';

class AllbrandMonitorPage extends TeamAllbrandMonitorPage {
  const AllbrandMonitorPage({super.key})
    : super(
        title: 'Monitor All Brand',
        rpcName: 'get_sator_allbrand_daily_monitor',
        principalParam: 'p_sator_id',
      );
}
