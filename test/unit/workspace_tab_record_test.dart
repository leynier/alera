import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceTabKind.fromJson', () {
    test('defaults null to terminal', () {
      expect(WorkspaceTabKind.fromJson(null), WorkspaceTabKind.terminal);
    });

    test('rejects invalid values', () {
      expect(() => WorkspaceTabKind.fromJson(42), throwsA(isA<StateError>()));
      expect(
        () => WorkspaceTabKind.fromJson('unknown'),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('WorkspaceTabRecord round-trips through json', () {
    final record = WorkspaceTabRecord(
      id: 'tab-1',
      workspaceId: 'workspace-1',
      kind: WorkspaceTabKind.browser,
      title: 'Docs',
      createdAt: DateTime.utc(2026, 5, 25),
      updatedAt: DateTime.utc(2026, 5, 25, 1),
      payload: const <String, Object?>{
        workspaceTabManualTitlePayloadKey: true,
        'url': 'https://example.com',
      },
    );

    final restored = WorkspaceTabRecord.fromJson(
      Map<String, Object?>.from(record.toMap()),
    );

    expect(restored, record);
    expect(restored.hasManualTitle, isTrue);
  });

  test('terminalSessionId uses payload value with tab id fallback', () {
    final now = DateTime.utc(2026, 5, 25);
    final legacy = WorkspaceTabRecord(
      id: 'tab-1',
      workspaceId: 'workspace-1',
      title: 'Terminal 1',
      createdAt: now,
      updatedAt: now,
    );
    final bound = WorkspaceTabRecord(
      id: 'tab-2',
      workspaceId: 'workspace-1',
      title: 'Terminal 2',
      createdAt: now,
      updatedAt: now,
      payload: const <String, Object?>{
        workspaceTabTerminalSessionIdPayloadKey: 'session-2',
      },
    );

    expect(legacy.terminalSessionId, 'tab-1');
    expect(bound.terminalSessionId, 'session-2');
  });
}
