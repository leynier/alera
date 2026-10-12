import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/application/project_hosts_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/background_setup_jobs.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/presentation/welcome_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_project_config.dart';

Future<WelcomeDashboardRecordedPrompt> pumpWelcomeDashboard(
  WidgetTester tester, {
  required WorkbenchState state,
  List<AgentProfile> profiles = const <AgentProfile>[],
  WelcomeDashboardTestController? controller,
  Size size = const Size(1200, 900),
  List<Override> extraOverrides = const <Override>[],
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final recorded = WelcomeDashboardRecordedPrompt();
  final jobs = _RecordingJobs(recorded);
  final configRepository = FakeProjectConfigRepository();
  addTearDown(configRepository.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _mergeOverrides(<Override>[
        workbenchControllerProvider.overrideWith(
          () => controller ?? WelcomeDashboardTestController(state),
        ),
        settingsControllerProvider.overrideWith(
          () => _WelcomeDashboardSettingsController(.defaults),
        ),
        agentProfilesProvider.overrideWith(
          () => _WelcomeDashboardAgentProfiles(profiles),
        ),
        backgroundSetupJobsProvider.overrideWith(() => jobs),
        projectHostsSupportedProvider.overrideWith((ref) async => false),
        projectConfigServiceProvider.overrideWithValue(
          ProjectConfigService(
            repository: configRepository,
            fileStore: FakeProjectConfigFileStore(),
          ),
        ),
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(_WelcomeDashboardRuntimeHostClient()),
        ),
      ], extraOverrides),
      child: const MaterialApp(home: WelcomeDashboard()),
    ),
  );
  await tester.pumpAndSettle();
  return recorded;
}

List<Override> _mergeOverrides(List<Override> base, List<Override> extra) {
  final replaced = <Object?>[for (final override in extra) override.origin];
  return <Override>[
    for (final override in base)
      if (!replaced.contains(override.origin)) override,
    ...extra,
  ];
}

AgentProfile welcomeDashboardProfile() {
  final now = DateTime.utc(2026, 5, 22);
  return AgentProfile(
    id: 'profile-1',
    name: 'Grok Build',
    agentType: 'grok',
    command: 'grok',
    createdAt: now,
    updatedAt: now,
  );
}

WorkbenchState welcomeDashboardProjectState({
  ProjectKind kind = ProjectKind.gitRepository,
}) {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
    kind: kind,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[workspace],
    },
    activeProjectId: project.id,
    bootstrapped: true,
  );
}

WorkbenchState welcomeDashboardRemoteState() {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/remote/alera',
    createdAt: now,
    updatedAt: now,
    primaryHostId: 'ssh-win',
    checkouts: const <ProjectCheckout>[
      ProjectCheckout(hostId: 'ssh-win', path: '/remote/alera'),
    ],
  );
  return WorkbenchState(
    projects: <Project>[project],
    activeProjectId: project.id,
    bootstrapped: true,
  );
}

SshTarget welcomeDashboardSshTarget({
  SshBootstrapStatus bootstrapStatus = SshBootstrapStatus.installed,
}) {
  final now = DateTime.utc(2026, 5, 22);
  return SshTarget(
    id: 'ssh-win',
    alias: 'Build Box',
    host: 'box.example.test',
    port: 22,
    username: 'leynier',
    authKind: SshAuthKind.agent,
    createdAt: now,
    updatedAt: now,
    bootstrapStatus: bootstrapStatus,
  );
}

class WelcomeDashboardHostSupport extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

final welcomeDashboardHostSupportProvider =
    NotifierProvider<WelcomeDashboardHostSupport, bool>(
      WelcomeDashboardHostSupport.new,
    );

class WelcomeDashboardRecordedPrompt {
  PromptWorkspaceCreateRequest? request;
}

class WelcomeDashboardBranchSource {
  Completer<List<String>>? hang;
  Object? error;
  List<String> names = const <String>['main'];
}

class WelcomeDashboardTestController extends WorkbenchController {
  WelcomeDashboardTestController(
    this._seed, {
    WelcomeDashboardBranchSource? branches,
  }) : _branches = branches ?? WelcomeDashboardBranchSource();

  final WorkbenchState _seed;
  final WelcomeDashboardBranchSource _branches;

  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<List<String>> listSourceBranches(Project project) async {
    final hang = _branches.hang;
    if (hang != null) {
      return hang.future;
    }
    final error = _branches.error;
    if (error != null) {
      throw error;
    }
    return _branches.names;
  }
}

class _WelcomeDashboardAgentProfiles extends AgentProfiles {
  _WelcomeDashboardAgentProfiles(this._profiles);

  final List<AgentProfile> _profiles;

  @override
  Future<List<AgentProfile>> build() async => _profiles;
}

class _RecordingJobs extends BackgroundSetupJobs {
  _RecordingJobs(this._recorded);

  final WelcomeDashboardRecordedPrompt _recorded;

  @override
  BackgroundSetupJobsState build() => const BackgroundSetupJobsState();

  @override
  Future<void>? enqueuePromptWorkspace(
    PromptWorkspaceCreateRequest request, {
    String? jobId,
  }) {
    _recorded.request = request;
    return Future<void>.value();
  }
}

class _WelcomeDashboardSettingsController(final AleraSettings _seed)
    extends SettingsController {
  @override
  AleraSettings build() => _seed;
}

class _WelcomeDashboardRuntimeHostClient implements RuntimeHostClient {
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    if (type == 'sshTarget.list') {
      return const <Object?>[];
    }
    return <String, Object?>{};
  }
}
