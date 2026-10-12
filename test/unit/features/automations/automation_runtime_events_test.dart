import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every automation catalog host event reaches runtimeEvents', () {
    // The connected event is synthesized by the client rather than forwarded
    // from the host, so it never goes through runtimeHostEventNames.
    final hostEvents = automationCatalogEvents.difference(<String>{
      aleraRuntimeHostConnectedEvent,
    });

    expect(hostEvents, isNotEmpty);
    expect(runtimeHostEventNames.containsAll(hostEvents), isTrue);
    expect(
      runtimeHostEventNames,
      containsAll(<String>[
        'automationsChanged',
        'automationRunChanged',
        'automationAttentionRequired',
      ]),
    );
  });
}
