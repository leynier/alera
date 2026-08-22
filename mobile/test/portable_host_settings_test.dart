import 'package:alera_mobile/src/features/settings/domain/portable_host_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('includes fx in the supported status integrations', () {
    expect(supportedAgentHooks, contains('fx'));
    expect(agentHookLabels['fx'], 'fx');

    final settings = PortableHostSettings.fromJson(<String, Object?>{
      'agentStatusHooks': <String, Object?>{'fx': true},
    });

    expect(settings.agentStatusHooks['fx'], isTrue);
  });
}
