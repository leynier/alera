import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_canvas/domain/agent_canvas.dart';
import 'package:alera/src/features/agent_canvas/presentation/agent_surface_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders only the pinned Agent Canvas component contract', (
    tester,
  ) async {
    final actions = <Map<String, Object?>>[];
    final canvas = _canvas();
    const renderer = PinnedGenUiAgentSurfaceRenderer();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => renderer.build(
              context,
              canvas: canvas,
              onAction: (action) async => actions.add(action),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Review Run'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('UnknownComponent'), findsNothing);

    await tester.tap(find.text('lib/main.dart'));
    await tester.tap(find.text('Approve'));
    await tester.pump();

    expect(actions, <Map<String, Object?>>[
      <String, Object?>{'kind': 'openFile', 'relativePath': 'lib/main.dart'},
      <String, Object?>{
        'kind': 'resolveDecision',
        'decisionId': 'decision-1',
        'resolution': 'Approve',
        'confirmed': true,
      },
    ]);
  });
}

AgentCanvas _canvas() {
  return AgentCanvas(
    id: 'canvas-1',
    workspaceId: 'workspace-1',
    terminalSessionId: 'session-1',
    agentType: 'codex',
    title: 'Review Run',
    state: .live,
    pinned: false,
    frozen: false,
    revision: 2,
    document: <String, Object?>{
      'version': 1,
      'components': <Object?>[
        <String, Object?>{
          'type': 'AgentRunHeader',
          'props': <String, Object?>{'title': 'Review Run', 'status': 'live'},
        },
        <String, Object?>{
          'type': 'FileReferenceList',
          'props': <String, Object?>{
            'files': <Object?>['lib/main.dart'],
          },
        },
        <String, Object?>{
          'type': 'DecisionRequest',
          'props': <String, Object?>{
            'question': 'Approve the plan?',
            'options': <Object?>['Approve'],
          },
        },
        <String, Object?>{
          'type': 'UnknownComponent',
          'props': <String, Object?>{},
        },
      ],
    },
    decisions: <AgentCanvasDecision>[
      AgentCanvasDecision(
        id: 'decision-1',
        canvasId: 'canvas-1',
        revision: 2,
        question: 'Approve the plan?',
        options: <Object?>['Approve'],
        state: .pending,
        createdAt: .utc(2026, 8, 3),
      ),
    ],
    createdAt: .utc(2026, 8, 3),
    updatedAt: .utc(2026, 8, 3),
  );
}
