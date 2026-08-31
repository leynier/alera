import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_status_bar.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('refreshes quotas after the TUI action button is disposed', (
    tester,
  ) async {
    final service = _PendingClaudeTuiService();
    var quotaBuilds = 0;
    final container = ProviderContainer(
      overrides: [
        agentQuotaServiceProvider.overrideWithValue(service),
        sshTargetsProvider.overrideWith(
          (ref) => Stream.value(const <SshTarget>[]),
        ),
        agentQuotaStateProvider.overrideWith((ref) async {
          quotaBuilds += 1;
          return AgentQuotaState.empty('local');
        }),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(agentQuotaStateProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(agentQuotaStateProvider.future);

    final snapshot = AgentQuotaSnapshot(
      provider: .claude,
      accountId: 'dev',
      displayName: 'Development',
      status: .unavailable,
      updatedAt: .utc(2026),
      error: 'OAuth unavailable',
      windows: const <AgentQuotaWindow>[],
      buckets: const <AgentQuotaBucket>[],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: AgentQuotaStatusBarView(
              hostId: 'local',
              snapshots: <AgentQuotaSnapshot>[snapshot],
              settings: const AgentQuotaHostSettings(
                enabledProviders: <AgentQuotaProviderId>[
                  AgentQuotaProviderId.claude,
                ],
                claudeProfiles: <ClaudeQuotaProfileSettings>[
                  ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'dev'),
                ],
              ),
              onRefresh: () {},
              onTogglePinned: (_, _) {},
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: .mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: .zero);
    await mouse.moveTo(tester.getCenter(find.text('ccdev')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Try With TUI'));
    await tester.pump();
    expect(service.callCount, 1);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
    service.completion.complete(snapshot);
    await tester.pump();
    await container.read(agentQuotaStateProvider.future);

    expect(tester.takeException(), isNull);
    expect(quotaBuilds, 2);
  });
}

class _PendingClaudeTuiService extends Fake implements AgentQuotaService {
  final completion = Completer<AgentQuotaSnapshot>();
  var callCount = 0;

  @override
  Future<AgentQuotaSnapshot> fetchClaudeTui({
    required String hostId,
    required SshTarget? target,
    required String accountId,
    String? displayName,
  }) {
    callCount += 1;
    return completion.future;
  }
}
