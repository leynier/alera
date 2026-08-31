import 'dart:async';
import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_mobile_codex_client.dart';

void main() {
  for (final resume in [false, true]) {
    for (final withSnapshot in [false, true]) {
      test(
        'mobile legacy transition retains submissions across its early event: $resume/$withSnapshot',
        () async {
          final gate = Completer<Map<String, Object?>>();
          final type = resume ? 'codex.thread.resume' : 'codex.thread.new';
          final client = FakeMobileCodexClient(
            initialThreadId: 'thread-old',
            requestHandler: (method, payload) =>
                method == type ? gate.future : null,
          );
          final container = ProviderContainer(
            overrides: [
              mobileCodexClientProvider(
                'legacy-transition',
              ).overrideWith((ref) async => client),
            ],
          );
          addTearDown(() {
            client.dispose();
            container.dispose();
          });
          final provider = mobileCodexControllerProvider(
            'legacy-transition',
            'tab-legacy-transition',
          );
          final listener = container.listen(
            provider,
            (_, _) {},
            fireImmediately: true,
          );
          addTearDown(listener.close);
          await container.read(provider.future);
          final controller = container.read(provider.notifier);
          final Future<Object?> transition = resume
              ? controller.resumeThread(
                  const MobileCodexThreadSummary(
                    id: 'thread-new',
                    title: 'New',
                  ),
                )
              : controller.newThread();
          await Future<void>.delayed(Duration.zero);
          await controller.send('Keep this submission');
          final snapshot = <String, Object?>{
            'timelineCells': <Object?>[],
            'pendingRequests': <Object?>[],
          };
          client.emit(
            MobileRuntimeEvent('codexThreadChanged', {
              'tabId': 'tab-legacy-transition',
              'threadId': 'thread-new',
              if (withSnapshot) 'snapshot': snapshot,
            }),
          );
          await Future<void>.delayed(Duration.zero);
          expect(container.read(provider).value!.queuedMessages, hasLength(1));
          expect(
            client.calls.where((call) => call.type == 'codex.turn.start'),
            isEmpty,
          );
          gate.complete({'threadId': 'thread-new', 'snapshot': snapshot});
          await transition;
          await Future<void>.delayed(Duration.zero);
          final starts = client.calls
              .where((call) => call.type == 'codex.turn.start')
              .toList();
          expect(starts, hasLength(1));
          expect(starts.single.payload['expectedThreadId'], 'thread-new');
          expect(
            starts.single.payload['input'],
            contains(equals({'type': 'text', 'text': 'Keep this submission'})),
          );
          expect(container.read(provider).value!.queuedMessages, isEmpty);
        },
      );
    }
  }
}
