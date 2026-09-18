import 'package:flutter/foundation.dart';

import '../platform/nirang_native.dart';

final deviceAccessBlock = ValueNotifier<String?>(null);
final deviceUpdateRequired = ValueNotifier<bool>(false);
final deviceAccessVerified = ValueNotifier<int>(0);

void markDeviceAccessBlocked([String? message]) {
  deviceAccessBlock.value = message?.trim().isNotEmpty == true
      ? message!.trim()
      : 'blocked_by_administrator';
}

void clearDeviceAccessBlocked() {
  deviceAccessBlock.value = null;
}

void markDeviceAccessVerified() {
  deviceAccessVerified.value++;
}

void markDeviceUpdateRequired() => deviceUpdateRequired.value = true;
void clearDeviceUpdateRequired() => deviceUpdateRequired.value = false;

abstract interface class DeviceRegistrationCoordinator {
  Future<bool> initialize();
  Future<void> verifyAccess();
  Future<void> accept();
  Future<void> exitApplication();
}

final class NativeDeviceRegistrationCoordinator
    implements DeviceRegistrationCoordinator {
  const NativeDeviceRegistrationCoordinator();

  @override
  Future<bool> initialize() => NirangNative.deviceRegistrationStatus();

  @override
  Future<void> verifyAccess() => NirangNative.verifyDeviceAccess();

  @override
  Future<void> accept() => NirangNative.acceptDeviceRegistration();

  @override
  Future<void> exitApplication() => NirangNative.exitApplication();
}
