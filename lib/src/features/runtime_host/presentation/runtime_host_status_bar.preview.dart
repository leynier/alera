import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/runtime_host/presentation/runtime_host_status_panel.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Runtime Chip Running', group: 'Status Bar')
Widget runtimeHostStatusChipRunningPreview() => Material(
  child: RuntimeHostStatusChip(
    snapshot: const RuntimeHostStatusSnapshot(
      running: true,
      bundledVersion: '1.2.3',
      runtimeHostVersion: '1.2.3',
      activeSessions: 2,
    ),
    loading: false,
    onPressed: () {},
  ),
);

@AleraPreview(name: 'Runtime Chip Update Available', group: 'Status Bar')
Widget runtimeHostStatusChipUpdatePreview() => Material(
  child: RuntimeHostStatusChip(
    snapshot: const RuntimeHostStatusSnapshot(
      running: true,
      bundledVersion: '1.3.0',
      runtimeHostVersion: '1.2.3',
      activeSessions: 1,
    ),
    loading: false,
    onPressed: () {},
  ),
);

@AleraPreview(name: 'Runtime Panel', group: 'Status Bar', size: Size(380, 560))
Widget runtimeHostStatusPanelPreview() => Material(
  child: RuntimeHostStatusPanel(
    snapshot: const RuntimeHostStatusSnapshot(
      running: true,
      bundledVersion: '1.3.0',
      bundledCommit: 'abcdef0',
      runtimeHostVersion: '1.2.3',
      runtimeHostCommit: '1234567',
      activeSessions: 2,
      activeAgents: 1,
    ),
    loading: false,
    stopRuntimeOnAppQuit: false,
    emptyShutdownDelaySeconds: 30,
    detachedSessionShutdownDelaySeconds: 3600,
    onRefresh: () {},
    onStart: () {},
    onStop: () {},
    onUpdate: () {},
    onStopRuntimeOnAppQuitChanged: (_) {},
    onEmptyShutdownDelayChanged: (_) {},
    onDetachedSessionShutdownDelayChanged: (_) {},
  ),
);
