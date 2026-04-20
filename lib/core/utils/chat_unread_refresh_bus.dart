import 'package:flutter/foundation.dart';

final ValueNotifier<int> chatUnreadRefreshTick = ValueNotifier<int>(0);

void notifyChatUnreadRefresh() {
  chatUnreadRefreshTick.value++;
}
