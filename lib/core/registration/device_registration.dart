import '../platform/nirang_native.dart';

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
