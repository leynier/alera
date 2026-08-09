import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test('mobile preserves legacy permission modes for an older host', () async {
    final client = FakeMobileCodexClient(supportsCodexTurnPolicy: false);
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-legacy',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider('host-legacy', 'tab-legacy');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);

    for (final mode in <String>[
      'untrusted',
      'on-request',
      'auto-review',
      'never',
    ]) {
      controller.setPermissionMode(mode);
      await controller.send('Inspect with $mode');
    }

    final turns = client.calls
        .where((call) => call.type == 'codex.turn.start')
        .toList(growable: false);
    expect(turns.map((turn) => turn.payload['approvalPolicy']), <String>[
      'untrusted',
      'on-request',
      'on-request',
      'never',
    ]);
    for (final turn in turns) {
      expect(turn.payload, isNot(contains('approvalsReviewer')));
      expect(turn.payload, isNot(contains('sandboxPolicy')));
    }
    expect(
      turns[2].payload['configuration'],
      containsPair('permissionMode', 'on-request'),
    );
  });
}
