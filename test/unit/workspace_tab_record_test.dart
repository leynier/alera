import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceTabKind.fromJson', () {
    test('defaults null to terminal', () {
      expect(WorkspaceTabKind.fromJson(null), WorkspaceTabKind.terminal);
    });

    test('rejects invalid values', () {
      expect(
        () => WorkspaceTabKind.fromJson(42),
        throwsA(isA<StateError>()),
      );
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
}
