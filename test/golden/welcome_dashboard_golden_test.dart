import 'dart:convert';

import 'package:alchemist/alchemist.dart';
import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/welcome_dashboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alera_golden_harness.dart';

void main() {
  runAleraGoldenTests(() {
    group('WelcomeDashboard goldens', () {
      goldenTest(
        'renders populated desktop dashboard',
        fileName: 'welcome_dashboard_populated_desktop',
        constraints: const .tightFor(width: 980, height: 720),
        pumpBeforeTest: precacheImages,
        builder: () => _GoldenDashboardFrame(state: _populatedState()),
      );

      goldenTest(
        'renders empty compact dashboard',
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

class const _GoldenDashboardFrame({required final WorkbenchState state})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultAssetBundle(
      bundle: _GoldenLogoAssetBundle(),
      child: ProviderScope(
        overrides: [
          workbenchControllerProvider.overrideWithValue(state),
          settingsControllerProvider.overrideWithValue(.defaults),
        ],
        child: const WelcomeDashboard(),
      ),
    );
  }
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

/// Populated state keeps New Workspace enabled in Quick Start for goldens.
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
