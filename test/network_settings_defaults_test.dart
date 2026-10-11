import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/platform/native_models.dart';

void main() {
  test(
    'pending native snapshot does not present obsolete enabled switches',
    () {
      const pending = NativeSettings();
      expect(pending.routingMode, 'bypassIran');
      expect(pending.routeOnly, isFalse);
      expect(pending.directDnsEnabled, isFalse);
      expect(pending.directDns, isEmpty);
    },
  );

  test('native snapshot remains authoritative for existing user switches', () {
    final saved = NativeSettings.fromMap({
      'routingMode': 'custom',
      'routeOnly': true,
      'directDnsEnabled': true,
      'directDns': '9.9.9.9',
      'enableLocalDns': false,
    });
    expect(saved.routeOnly, isTrue);
    expect(saved.directDnsEnabled, isTrue);
    expect(saved.directDns, '9.9.9.9');
    expect(saved.enableLocalDns, isFalse);
    expect(saved.routingMode, 'custom');
  });
}
