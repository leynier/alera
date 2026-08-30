import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/ai_assist/application/agent_title_providers.dart';
import 'package:alera/src/features/mobile_emulator/application/mobile_emulator_lease_coordinator.dart';
import 'package:alera/src/features/mobile_emulator/application/mobile_emulator_providers.dart';
import 'package:alera/src/features/mobile_emulator/infra/mobile_emulator_service.dart';
import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_surface.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_tab_attention.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/workspace_workbench_view.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

part 'mobile_emulator_workbench_visibility_test_cases.dart';

void main() {
  _registerWorkbenchEmulatorVisibilityTests();
  testWidgets('releases the emulator lease after the surface is unmounted', (
    tester,
  ) async {
    final client = _SurfaceRuntimeHostClient();
    final service = MobileEmulatorService(client);
    final leases = MobileEmulatorLeaseCoordinator(service);
    addTearDown(leases.dispose);
    addTearDown(service.dispose);

    Widget buildSurface(Widget child) {
      return ProviderScope(
        overrides: [
          mobileEmulatorServiceProvider.overrideWithValue(service),
          mobileEmulatorLeaseCoordinatorProvider.overrideWithValue(leases),
        ],
        child: MaterialApp(theme: buildAleraDarkTheme(), home: child),
      );
    }

    await tester.pumpWidget(
      buildSurface(
        MobileEmulatorSurface(
          workspace: _workspace,
          tab: _tab,
          autofocus: false,
        ),
      ),
    );
    await tester.pump();
    expect(client.acquireRequests, 1);

    await tester.pumpWidget(buildSurface(const SizedBox.shrink()));

    expect(tester.takeException(), isNull);

    await tester.pump(MobileEmulatorLeaseCoordinator.releaseGrace);
    expect(client.releaseRequests, 1);
  });
}

final DateTime _now = DateTime.utc(2026, 8, 22);

final Workspace _workspace = Workspace(
  id: 'workspace-1',
  projectId: 'project-1',
  name: 'Alera',
  path: '/workspace',
  createdAt: _now,
  updatedAt: _now,
  kind: WorkspaceKind.main,
  status: WorkspaceStatus.active,
);

final WorkspaceTabRecord _tab = WorkspaceTabRecord(
  id: 'tab-1',
  workspaceId: _workspace.id,
  title: 'Pixel 9',
  createdAt: _now,
  updatedAt: _now,
  kind: WorkspaceTabKind.mobileEmulator,
);

final class _SurfaceRuntimeHostClient implements RuntimeHostClient {
  final requests = <String>[];
  int acquireRequests = 0;
  int releaseRequests = 0;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents =>
      const Stream<RuntimeHostEvent>.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add(type);
    return switch (type) {
      'status.get' => <String, Object?>{
        'runtimeCapabilities': <String>[
          aleraRuntimeHostMobileEmulatorCapability,
        ],
      },
      'emulator.acquire' => _session(acquired: true),
      'emulator.release' => _session(acquired: false),
      _ => throw StateError('Unexpected runtime request: $type'),
    };
  }

  Map<String, Object?> _session({required bool acquired}) {
    if (acquired) {
      acquireRequests += 1;
    } else {
      releaseRequests += 1;
    }
    return <String, Object?>{
      'ok': true,
      'session': <String, Object?>{
        'id': 'session-1',
        'state': acquired ? 'running' : 'released',
        'platform': 'android',
        'deviceId': 'pixel-9',
      },
    };
  }
}
