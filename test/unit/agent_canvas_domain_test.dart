import 'package:alera/src/features/agent_canvas/domain/agent_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies retained terminal states as history', () {
    expect(AgentCanvasState.completed.isHistory, isTrue);
    expect(AgentCanvasState.orphaned.isHistory, isTrue);
    expect(AgentCanvasState.closed.isHistory, isTrue);
    expect(AgentCanvasState.live.isHistory, isFalse);
    expect(AgentCanvasState.waiting.isHistory, isFalse);
  });

  test('decodes a runtime canvas without losing typed decisions', () {
    final canvas = AgentCanvas.fromJson(<String, Object?>{
      'id': 'canvas-1',
      'workspaceId': 'workspace-1',
      'terminalSessionId': 'session-1',
      'tabId': 'tab-1',
      'agentType': 'codex',
      'title': 'Run',
      'state': 'waiting',
      'pinned': false,
      'frozen': false,
      'revision': 1,
      'finalRevision': null,
      'document': <String, Object?>{'version': 1, 'components': <Object?>[]},
      'decisions': <Object?>[
        <String, Object?>{
          'id': 'decision-1',
          'canvasId': 'canvas-1',
          'revision': 1,
          'question': 'Continue?',
          'options': <Object?>['Yes'],
          'state': 'pending',
          'resolution': null,
          'createdAt': '2026-08-03T12:00:00Z',
          'resolvedAt': null,
          'expiresAt': null,
        },
      ],
      'createdAt': '2026-08-03T12:00:00Z',
      'updatedAt': '2026-08-03T12:00:00Z',
      'completedAt': null,
      'expiresAt': null,
    });

    expect(canvas.isActive, isTrue);
    expect(canvas.hasPendingDecision, isTrue);
    expect(canvas.decisions.single.id, 'decision-1');
    expect(canvas.components, <Object?>[]);
    expect(
      AgentCanvasDecision.fromJson(<String, Object?>{
        'id': 'decision-2',
        'canvasId': 'canvas-1',
        'revision': 1,
        'question': 'Continue?',
        'options': <Object?>['No'],
        'state': 'resolved',
        'resolution': 'No',
        'createdAt': '2026-08-03T12:00:00Z',
        'resolvedAt': '2026-08-03T12:01:00Z',
        'expiresAt': null,
      }).isPending,
      isFalse,
    );
    expect(
      AgentCanvas.fromJson(<String, Object?>{
        'id': 'canvas-2',
        'workspaceId': 'workspace-1',
        'terminalSessionId': 'session-1',
        'tabId': null,
        'agentType': 'codex',
        'title': 'Done',
        'state': 'completed',
        'pinned': false,
        'frozen': true,
        'revision': 2,
        'finalRevision': 2,
        'document': <String, Object?>{'version': 1},
        'decisions': <Object?>[],
        'createdAt': '2026-08-03T12:00:00Z',
        'updatedAt': '2026-08-03T12:02:00Z',
        'completedAt': '2026-08-03T12:02:00Z',
        'expiresAt': null,
      }).isActive,
      isFalse,
    );
  });

  test('decodes canvas events from runtime JSON', () {
    final event = AgentCanvasEvent.fromJson(<String, Object?>{
      'sequence': 7,
      'canvasId': 'canvas-1',
      'workspaceId': 'workspace-1',
      'eventType': 'agentCanvasChanged',
      'payload': <String, Object?>{'state': 'live'},
      'createdAt': '2026-08-03T12:00:00Z',
    });

    expect(event.sequence, 7);
    expect(event.payload['state'], 'live');
  });
}
