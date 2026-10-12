import 'dart:convert';

import 'package:alchemist/alchemist.dart';
import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/application/project_hosts_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/welcome_dashboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alera_golden_harness.dart';

final AgentProfile _grokProfile = AgentProfile(
  id: 'profile-grok',
  name: 'Grok Build',
  agentType: 'grok',
  command: 'grok',
  createdAt: DateTime.utc(2026, 5, 25),
  updatedAt: DateTime.utc(2026, 5, 25),
);

void main() {
  runAleraGoldenTests(() {
    group('WelcomeDashboard goldens', () {
      goldenTest(
        'renders populated desktop composer',
        fileName: 'welcome_dashboard_populated_desktop',
        constraints: const .tightFor(width: 980, height: 720),
        pumpBeforeTest: precacheImages,
        builder: () => _GoldenDashboardFrame(
          state: _populatedState(),
          profiles: <AgentProfile>[_grokProfile],
        ),
      );

      goldenTest(
        'renders empty compact composer',
        fileName: 'welcome_dashboard_empty_compact',
        constraints: const .tightFor(width: 390, height: 760),
        pumpBeforeTest: precacheImages,
        builder: () => const _GoldenDashboardFrame(
          state: WorkbenchState(bootstrapped: true),
        ),
      );
    });
  });
}

class _GoldenDashboardFrame extends StatelessWidget {
  const _GoldenDashboardFrame({
    required this.state,
    this.profiles = const <AgentProfile>[],
  });

  final WorkbenchState state;
  final List<AgentProfile> profiles;

  @override
  Widget build(BuildContext context) {
    return DefaultAssetBundle(
      bundle: _GoldenLogoAssetBundle(),
      child: ProviderScope(
        overrides: [
          // Root providers, overridden only inside this golden frame.
          // ignore: riverpod_lint/scoped_providers_should_specify_dependencies
          workbenchControllerProvider.overrideWithValue(state),
          // ignore: riverpod_lint/scoped_providers_should_specify_dependencies
          settingsControllerProvider.overrideWithValue(.defaults),
          // ignore: riverpod_lint/scoped_providers_should_specify_dependencies
          agentProfilesProvider.overrideWith(
            () => _GoldenAgentProfiles(profiles),
          ),
          // ignore: riverpod_lint/scoped_providers_should_specify_dependencies
          sshTargetsProvider.overrideWith(
            (ref) => Stream<List<SshTarget>>.value(const <SshTarget>[]),
          ),
          // ignore: riverpod_lint/scoped_providers_should_specify_dependencies
          projectHostsSupportedProvider.overrideWith((ref) async => false),
        ],
        child: const WelcomeDashboard(),
      ),
    );
  }
}

class _GoldenAgentProfiles extends AgentProfiles {
  _GoldenAgentProfiles(this._profiles);

  final List<AgentProfile> _profiles;

  @override
  Future<List<AgentProfile>> build() async => _profiles;
}

class _GoldenLogoAssetBundle extends CachingAssetBundle {
  static const String _logoPath = 'assets/logo/alera-logo-white.png';
  static final ByteData _logoBytes = .sublistView(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAALklEQVR42u3OQQEAAAQEMPQPeU2I4bMlWCfZejT1TEBAQEBAQEBAQEBAQEBA4ABySAPfxFCIhQAAAABJRU5ErkJggg==',
    ),
  );

  @override
  Future<ByteData> load(String key) async {
    if (key == _logoPath) {
      return _logoBytes;
    }
    return rootBundle.load(key);
  }
}

/// Populated state keeps an active workspace so the parent chip is visible.
WorkbenchState _populatedState() {
  final now = DateTime.utc(2026, 5, 25);
  final project = Project(
    id: 'project-alera',
    name: 'Alera',
    repoPath: '/projects/alera',
    createdAt: now,
    updatedAt: now,
  );
  final mainWorkspace = Workspace(
    id: 'workspace-main',
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
      project.id: <Workspace>[mainWorkspace],
    },
    activeProjectId: project.id,
    bootstrapped: true,
  );
}
