import 'package:flutter/foundation.dart';

import '../platform/nirang_native.dart';

final deviceAccessBlock = ValueNotifier<String?>(null);

void markDeviceAccessBlocked([String? message]) {
  deviceAccessBlock.value = message?.trim().isNotEmpty == true
      ? message!.trim()
      : 'blocked_by_administrator';
}

void clearDeviceAccessBlocked() {
  deviceAccessBlock.value = null;
}

abstract interface class DeviceRegistrationCoordinator {
  Future<bool> initialize();
  Future<void> accept();
  Future<void> exitApplication();
}

final class NativeDeviceRegistrationCoordinator
    implements DeviceRegistrationCoordinator {
  const NativeDeviceRegistrationCoordinator();

  @override
  Future<bool> initialize() => NirangNative.deviceRegistrationStatus();

  @override
  Future<void> accept() => NirangNative.acceptDeviceRegistration();

  @override
  Future<void> exitApplication() => NirangNative.exitApplication();
}
