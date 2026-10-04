import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/features/automations/presentation/automations_page.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'run_board_widget_harness.dart';

typedef AutomationRequest = ({String type, Map<String, Object?> payload});

/// Runtime double for the automation verbs. Responses are plain JSON, the way
/// the runtime sends them, so parsing is exercised too.
class FakeAutomationRuntime
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  FakeAutomationRuntime({
    this.capabilities = const <String>{
      automationsAuthoringCapability,
      automationTerminalObserveCapability,
    },
  });

  Set<String> capabilities;
  final List<AutomationRequest> requests = <AutomationRequest>[];
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();
  List<Map<String, Object?>> automations = <Map<String, Object?>>[];
  Map<String, Map<String, Object?>> details = <String, Map<String, Object?>>{};
  Map<String, Object?> runNowResult = automationRunJson(status: 'dispatching');
  Map<String, Object?> readiness = const <String, Object?>{
    'ready': true,
    'issues': <Object?>[],
  };
  List<Map<String, Object?>> runs = <Map<String, Object?>>[];

  void emit(String name, [Map<String, Object?> payload = const {}]) =>
      _events.add(RuntimeHostEvent(name, payload));

  Iterable<AutomationRequest> requestsOf(String type) =>
      requests.where((request) => request.type == type);

  Future<void> dispose() => _events.close();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capabilities.contains(capability);

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add((type: type, payload: payload));
    return switch (type) {
      'automation.list' => <String, Object?>{'items': automations},
      'automation.show' =>
        details[payload['id']] ??
            <String, Object?>{
              'automation': automations.firstWhere(
                (item) => item['id'] == payload['id'],
                orElse: () => automationJson(id: '${payload['id']}'),
              ),
              'runs': runs,
              'audit': <Object?>[],
              'occurrences': <Object?>[],
            },
      'automation.runs' => <String, Object?>{'items': runs},
      'automation.runNow' => runNowResult,
      'automation.readiness' => readiness,
      'automation.previewSchedule' => <String, Object?>{
        'occurrences': <Object?>[
          <String, Object?>{'localTime': '2026-10-05 09:00'},
        ],
        'timezone': 'America/Havana',
      },
      'automation.create' => <String, Object?>{
        'automation': automationJson(
          id: 'created',
          state: (payload['automation'] as Map?)?['state'] == 'draft'
              ? 'draft'
              : 'active',
        ),
      },
      'automation.patch' => <String, Object?>{
        'automation': automationJson(id: '${payload['id']}'),
      },
      'automation.tags' ||
      'automation.templates' => <String, Object?>{'items': <Object?>[]},
      _ => automationJson(id: '${payload['id'] ?? 'automation'}'),
    };
  }
}

Map<String, Object?> automationJson({
  String id = 'nightly',
  String name = 'Nightly Review',
  String state = 'active',
  Map<String, Object?>? target,
  Map<String, Object?>? association,
  Map<String, Object?>? attention,
  Map<String, Object?>? readiness,
  String? schedule,
}) => <String, Object?>{
  'id': id,
  'slug': id,
  'name': name,
  'description': '',
  'promptTemplate': 'Review open work',
  'schedule': <String, Object?>{
    'recurring': <String, Object?>{
      'cron': schedule ?? '0 9 * * 1-5',
      'timezone': 'America/Havana',
    },
  },
  'target':
      target ??
      <String, Object?>{
        'freshTab': <String, Object?>{
          'workspaceId': 'ws-1',
          'agentProfileId': 'codex',
        },
      },
  'state': state,
  'revision': 3,
  'association': ?association,
  'attention': ?attention,
  'readiness': ?readiness,
};

Map<String, Object?> automationRunJson({
  String id = 'run-1',
  String automationId = 'nightly',
  int number = 1,
  String status = 'dispatched',
  String? workspaceId = 'ws-1',
  String? tabId = 'main-session-1',
  bool takenOver = false,
  Map<String, Object?>? recovery,
  String? continueFromRunId,
}) => <String, Object?>{
  'id': id,
  'automationId': automationId,
  'number': number,
  'status': status,
  'trigger': 'scheduled',
  'workspaceId': ?workspaceId,
  'tabId': ?tabId,
  'takenOver': takenOver,
  'recovery': ?recovery,
  'continueFromRunId': ?continueFromRunId,
  'targetIdentity': <String, Object?>{'workspaceId': ?workspaceId},
};

AutomationWorkbenchContext automationTestContext() {
  final state = boardWorkbenchState();
  final now = DateTime.utc(2026, 10);
  return AutomationWorkbenchContext(
    projects: state.projects,
    workspaces: state.workspacesByProject.values
        .expand((item) => item)
        .toList(),
    profiles: <AgentProfile>[
      AgentProfile(
        id: 'codex',
        name: 'Codex Daily',
        agentType: 'codex',
        command: 'codex',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    tabsByWorkspace: state.tabsByWorkspace,
  );
}

ProviderContainer automationContainer(
  FakeAutomationRuntime runtime, {
  BoardTestWorkbench? workbench,
  AutomationWorkbenchContext? context,
}) => ProviderContainer(
  overrides: [
    automationRepositoryProvider.overrideWithValue(
      RuntimeAutomationRepository(runtime),
    ),
    automationWorkbenchContextProvider.overrideWithValue(
      context ?? automationTestContext(),
    ),
    terminalRuntimeProvider.overrideWith((ref) {
      final runtime = XtermTerminalRuntime();
      ref.onDispose(runtime.dispose);
      return runtime;
    }),
    workbenchControllerProvider.overrideWith(
      () => workbench ?? BoardTestWorkbench(),
    ),
  ],
);

class AutomationsTestApp extends StatelessWidget {
  const AutomationsTestApp({super.key, required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) =>
              ref.watch(automationsNavigationProvider).visible
              ? const AutomationsPage()
              : const Center(child: Text('Workspace')),
        ),
      ),
    ),
  );
}
