import 'dart:async';

import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';

typedef AutomationCall = ({String type, Map<String, Object?> payload});

/// Paired runtime double for the Automations screens. Responses are the JSON
/// the runtime sends.
class FakeAutomationClient implements MobileAutomationClient {
  FakeAutomationClient({
    Set<String>? capabilities,
    List<Map<String, Object?>>? automations,
  }) : runtimeCapabilities =
           capabilities ??
           <String>{
             'automationsV1',
             automationsAuthoringCapability,
             automationTerminalObserveCapability,
           },
       automations =
           automations ?? <Map<String, Object?>>[mobileAutomationJson()];

  @override
  Set<String> runtimeCapabilities;
  List<Map<String, Object?>> automations;
  List<Map<String, Object?>> runs = <Map<String, Object?>>[];
  Map<String, Object?> runNowResult = <String, Object?>{
    'id': 'run-9',
    'number': 9,
    'status': 'dispatching',
  };
  final List<AutomationCall> calls = <AutomationCall>[];
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();

  Iterable<AutomationCall> callsOf(String type) =>
      calls.where((call) => call.type == type);

  void emit(String name, [Map<String, Object?> payload = const {}]) =>
      _events.add(MobileRuntimeEvent(name, payload));

  Future<void> dispose() => _events.close();

  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;

  @override
  bool get supportsAutomations => runtimeCapabilities.contains('automationsV1');

  @override
  bool get supportsWorkspaceSections => false;

  @override
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    calls.add((type: type, payload: payload));
    return switch (type) {
      'automation.list' => <String, Object?>{'items': automations},
      'automation.show' => <String, Object?>{
        'automation': automations.firstWhere(
          (item) => item['id'] == payload['id'],
        ),
        'runs': runs,
        'audit': <Object?>[],
        'occurrences': <Object?>[],
      },
      'automation.runs' => <String, Object?>{'items': runs},
      'automation.runNow' => runNowResult,
      'automation.readiness' => <String, Object?>{
        'ready': true,
        'issues': <Object?>[],
      },
      'automation.previewSchedule' => <String, Object?>{
        'occurrences': <Object?>[],
        'timezone': 'UTC',
      },
      'automation.create' => <String, Object?>{
        'automation': mobileAutomationJson(id: 'created'),
      },
      'checkout.list' => <Object?>[],
      _ => <String, Object?>{},
    };
  }

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async => Map<String, Object?>.from(
    await request(type, payload) as Map? ?? const <String, Object?>{},
  );

  @override
  Future<List<Object?>> requestList(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async => List<Object?>.from(await request(type, payload) as List? ?? []);

  @override
  Future<List<ProjectSummary>> listProjects() async => const <ProjectSummary>[
    ProjectSummary(id: 'project-1', name: 'Alera', repoPath: '/alera'),
  ];

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async =>
      const <WorkspaceSummary>[
        WorkspaceSummary(
          id: 'ws-1',
          projectId: 'project-1',
          name: 'Main',
          path: '/alera',
          branch: 'main',
        ),
      ];

  @override
  Future<List<AgentProfileSummary>> listAgentProfiles() async =>
      const <AgentProfileSummary>[
        AgentProfileSummary(
          id: 'codex',
          name: 'Codex Daily',
          agentType: 'codex',
        ),
      ];

  @override
  Future<List<WorkspaceSectionSummary>> listWorkspaceSections() async =>
      const <WorkspaceSectionSummary>[];

  @override
  Future<List<WorkspaceTabSummary>> listTabs(String workspaceId) async =>
      const <WorkspaceTabSummary>[];
}

Map<String, Object?> mobileAutomationJson({
  String id = 'nightly',
  String name = 'Nightly Review',
  String state = 'active',
}) => <String, Object?>{
  'id': id,
  'slug': id,
  'name': name,
  'promptTemplate': 'Review open work',
  'schedule': <String, Object?>{
    'recurring': <String, Object?>{'cron': '0 9 * * 1-5', 'timezone': 'UTC'},
  },
  'target': <String, Object?>{
    'freshTab': <String, Object?>{
      'workspaceId': 'ws-1',
      'agentProfileId': 'codex',
    },
  },
  'state': state,
  'revision': 2,
};
