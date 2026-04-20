import 'package:flutter/foundation.dart';

final ValueNotifier<int> avatarRefreshTick = ValueNotifier<int>(0);

void notifyAvatarRefresh() {
  avatarRefreshTick.value++;
}
