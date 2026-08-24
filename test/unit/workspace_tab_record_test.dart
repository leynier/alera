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
      kind: WorkspaceTabKind.markdownViewer,
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

  test('detects markdown file paths case-insensitively', () {
    expect(isWorkspaceMarkdownFilePath('readme.md'), isTrue);
    expect(isWorkspaceMarkdownFilePath('README.MD'), isTrue);
    expect(isWorkspaceMarkdownFilePath('readme.markdown'), isFalse);
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

  test('terminal lifecycle flags reflect their payload values', () {
    final now = DateTime.utc(2026, 5, 25);
    final regular = WorkspaceTabRecord(
      id: 'tab-1',
      workspaceId: 'workspace-1',
      title: 'Terminal 1',
      createdAt: now,
      updatedAt: now,
    );
    final eager = WorkspaceTabRecord(
      id: 'tab-2',
      workspaceId: 'workspace-1',
      title: 'Terminal 2',
      createdAt: now,
      updatedAt: now,
      payload: const <String, Object?>{
        workspaceTabSpawnOnCreatePayloadKey: true,
        workspaceTabAutoCloseOnSuccessPayloadKey: true,
      },
    );

    expect(regular.spawnOnCreate, isFalse);
    expect(regular.autoCloseOnSuccess, isFalse);
    expect(eager.spawnOnCreate, isTrue);
    expect(eager.autoCloseOnSuccess, isTrue);
  });

  test(
    'terminal pulse configuration defaults and round-trips through payload',
    () {
      final now = DateTime.utc(2026, 8, 12);
      final regular = WorkspaceTabRecord(
        id: 'tab-1',
        workspaceId: 'workspace-1',
        title: 'Terminal 1',
        createdAt: now,
        updatedAt: now,
      );
      final configured = WorkspaceTabRecord(
        id: 'tab-2',
        workspaceId: 'workspace-1',
        title: 'Terminal 2',
        createdAt: now,
        updatedAt: now,
        payload: <String, Object?>{
          workspaceTabTerminalPulsePayloadKey: const TerminalPulseConfiguration(
            command: 'R',
            appendEnter: false,
            delayMilliseconds: 1500,
          ).toJson(),
        },
      );

      expect(regular.terminalPulse, const TerminalPulseConfiguration());
      expect(
        configured.terminalPulse,
        const TerminalPulseConfiguration(
          command: 'R',
          appendEnter: false,
          delayMilliseconds: 1500,
        ),
      );
      expect(
        WorkspaceTabRecord.fromJson(
          Map<String, Object?>.from(configured.toMap()),
        ).terminalPulse,
        configured.terminalPulse,
      );
    },
  );

  test('terminal pulse configuration copies values and has a stable hash', () {
    const original = TerminalPulseConfiguration();
    const expected = TerminalPulseConfiguration(
      command: 'R',
      appendEnter: false,
      delayMilliseconds: 1500,
    );

    expect(
      original.copyWith(
        command: 'R',
        appendEnter: false,
        delayMilliseconds: 1500,
      ),
      expected,
    );
    expect(original.copyWith(), original);
    expect(expected.hashCode, expected.hashCode);
  });

  test(
    'browser state uses the tab id as page identity and default profile',
    () {
      final now = DateTime.utc(2026, 7, 27);
      final blank = WorkspaceTabRecord(
        id: 'browser-1',
        workspaceId: 'workspace-1',
        kind: WorkspaceTabKind.browser,
        title: 'New Tab',
        createdAt: now,
        updatedAt: now,
      );
      final restored = WorkspaceTabRecord(
        id: 'browser-2',
        workspaceId: 'workspace-1',
        kind: WorkspaceTabKind.browser,
        title: 'Alera',
        createdAt: now,
        updatedAt: now,
        payload: const <String, Object?>{
          workspaceTabBrowserProfileIdPayloadKey: 'research',
          workspaceTabBrowserUrlPayloadKey: 'https://alera.dev',
          workspaceTabBrowserRuntimeTitlePayloadKey: 'Alera',
        },
      );

      expect(blank.id, 'browser-1');
      expect(blank.browserProfileId, 'default');
      expect(blank.browserUrl, isNull);
      expect(restored.browserProfileId, 'research');
      expect(restored.browserUrl, 'https://alera.dev');
      expect(restored.browserRuntimeTitle, 'Alera');
    },
  );

  test('preview payload round-trips and file slots skip merman tabs', () {
    final now = DateTime.utc(2026, 5, 25);
    final preview = WorkspaceTabRecord(
      id: 'tab-1',
      workspaceId: 'workspace-1',
      kind: WorkspaceTabKind.editor,
      title: 'main.dart',
      createdAt: now,
      updatedAt: now,
      payload: const <String, Object?>{
        workspaceTabFilePathPayloadKey: 'lib/main.dart',
        workspaceTabPreviewPayloadKey: true,
      },
    );
    final restored = WorkspaceTabRecord.fromJson(
      Map<String, Object?>.from(preview.toMap()),
    );
    final merman = WorkspaceTabRecord(
      id: 'tab-2',
      workspaceId: 'workspace-1',
      kind: WorkspaceTabKind.editor,
      title: 'diagram.mmd preview',
      createdAt: now,
      updatedAt: now,
      payload: const <String, Object?>{
        workspaceTabFilePathPayloadKey: 'docs/diagram.mmd',
        workspaceTabPreviewPayloadKey: true,
        workspaceTabFileRolePayloadKey: workspaceTabFileRoleMermanPreview,
      },
    );
    final terminalPreview = WorkspaceTabRecord(
      id: 'tab-3',
      workspaceId: 'workspace-1',
      title: 'Terminal 1',
      createdAt: now,
      updatedAt: now,
      payload: const <String, Object?>{workspaceTabPreviewPayloadKey: true},
    );
    final permanent = WorkspaceTabRecord(
      id: 'tab-4',
      workspaceId: 'workspace-1',
      kind: WorkspaceTabKind.editor,
      title: 'main.dart',
      createdAt: now,
      updatedAt: now,
      payload: const <String, Object?>{
        workspaceTabFilePathPayloadKey: 'lib/main.dart',
      },
    );

    expect(preview.isPreview, isTrue);
    expect(preview.isFilePreviewSlot, isTrue);
    expect(restored.isPreview, isTrue);
    expect(restored.isFilePreviewSlot, isTrue);
    expect(merman.isPreview, isTrue);
    expect(merman.isFilePreviewSlot, isFalse);
    expect(terminalPreview.isPreview, isTrue);
    expect(terminalPreview.isFilePreviewSlot, isFalse);
    expect(permanent.isPreview, isFalse);
    expect(permanent.isFilePreviewSlot, isFalse);
  });
}
