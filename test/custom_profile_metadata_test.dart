import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/platform/native_models.dart';

void main() {
  test('typed metadata retains engine and kind through latency updates', () {
    final profile = ServerInfo.fromMap({
      'id': 'custom_aether_1',
      'name': 'اتر',
      'protocol': 'AETHER',
      'engine': 'aether',
      'profileKind': 'aether',
      'profileEditable': false,
    });
    expect(profile.profileKind, 'aether');
    expect(profile.engine, 'aether');
    expect(profile.copyWith(ping: 21).profileKind, 'aether');
    expect(profile.copyWith(selected: true).engine, 'aether');
    expect(profile.profileEditable, false);
  });
  test('legacy bridge metadata remains an ordinary Xray profile', () {
    final profile = ServerInfo.fromMap({'id': 'old', 'name': 'old'});
    expect(profile.profileKind, 'uri');
    expect(profile.engine, 'xray');
  });
  test('Psiphon branding survives selection and latency metadata updates', () {
    final profile = ServerInfo.fromMap({
      'id': 'aether',
      'name': 'Aether',
      'engine': 'aether',
      'profileKind': 'aether',
      'psiphonEnabled': true,
      'countryCode': 'JP',
    });
    expect(profile.psiphonEnabled, isTrue);
    expect(profile.copyWith(ping: 24, selected: true).psiphonEnabled, isTrue);
    expect(
      ServerInfo.fromMap({'id': 'legacy', 'name': 'legacy'}).psiphonEnabled,
      isFalse,
    );
  });
}
