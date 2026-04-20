import 'package:flutter/foundation.dart';

final ValueNotifier<int> promotorHomeRefreshTick = ValueNotifier<int>(0);

void notifyPromotorHomeRefresh() {
  promotorHomeRefreshTick.value++;
}
