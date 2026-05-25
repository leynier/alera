import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/app.dart';
import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adds a local folder and opens its terminal workspace', (
    tester,
  ) async {
    final tempRoot = await Directory.systemTemp.createTemp('alera-e2e-');
    addTearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final projectDir = Directory(p.join(tempRoot.path, 'sample-project'))
      ..createSync(recursive: true);
    Directory(p.join(projectDir.path, '.git')).createSync();

    final db = AleraDatabase(executor: NativeDatabase.memory());
    var dbClosed = false;
    Future<void> closeDb() async {
      if (dbClosed) {
        return;
      }
      dbClosed = true;
      await db.close();
    }

    addTearDown(closeDb);

    final terminalRuntime = _E2eTerminalRuntime();
    addTearDown(terminalRuntime.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith((ref) async {
            ref.onDispose(closeDb);
            return db;
          }),
          processRunnerProvider.overrideWithValue(_E2eProcessRunner()),
          terminalRuntimeProvider.overrideWith((ref) => terminalRuntime),
        ],
        child: const AleraApp(),
      ),
    );

    await _pumpUntilFound(tester, find.text('No projects yet'));

    await tester.tap(find.text('Add project').last);
    await _pumpUntilFound(tester, find.byType(AddProjectDialog));

    final projectPathField = find.descendant(
      of: find.byType(AddProjectDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(projectPathField.first, projectDir.path);
    await tester.pump();

    final submitButton = find.descendant(
      of: find.byType(AddProjectDialog),
      matching: find.widgetWithText(FilledButton, 'Add project'),
    );
    await tester.tap(submitButton);

    await _pumpUntilFound(tester, find.text('Main'));

    await tester.tap(find.text('Main').last);
    await _pumpUntilFound(tester, find.byTooltip('New terminal'));
    await _pumpUntilFound(tester, find.text('E2E terminal: Terminal 1'));

    await tester.tap(find.byTooltip('New terminal').first);
    await _pumpUntilFound(tester, find.text('E2E terminal: Terminal 2'));

    expect(
      terminalRuntime.startedTitles,
      containsAll(<String>['Terminal 1', 'Terminal 2']),
    );
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 60,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (tester.any(finder)) {
      return;
    }
  }
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .take(40)
      .join(' | ');
  fail('Expected to find $finder. Visible text: $visibleText');
}

class _E2eProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (executable == 'git' &&
        arguments.contains('rev-parse') &&
        arguments.contains('--is-inside-work-tree')) {
      return const ProcessRunOutput(exitCode: 1, stdout: '', stderr: '');
    }
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError(
      'The E2E smoke flow uses a fake terminal runtime.',
    );
  }
}

class _E2eTerminalRuntime implements TerminalRuntime {
  final Map<String, _E2eTerminalSessionHandle> _sessions =
      <String, _E2eTerminalSessionHandle>{};
  final StreamController<TerminalRuntimeExitEvent> _exitController =
      StreamController<TerminalRuntimeExitEvent>.broadcast();

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  Iterable<String> get startedTitles => _sessions.values
      .where((session) => session.isRunning)
      .map((session) => session.displayTitle);

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _sessions.putIfAbsent(
      tab.id,
      () => _E2eTerminalSessionHandle(workspace: workspace, tab: tab),
    );
  }

  @override
  void closeTab(String tabId) {
    _sessions.remove(tabId)?.dispose();
  }

  @override
  void closeWorkspace(String workspaceId) {
    final tabIds = _sessions.entries
        .where((entry) => entry.value.workspaceId == workspaceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final tabId in tabIds) {
      closeTab(tabId);
    }
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    unawaited(_exitController.close());
  }
}

class _E2eTerminalSessionHandle extends TerminalSessionHandle {
  _E2eTerminalSessionHandle({required this.workspace, required this.tab});

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  bool _started = false;

  @override
  String get displayTitle => tab.title;

  @override
  String? get errorMessage => null;

  @override
  bool get isRunning => _started;

  @override
  bool get isStarting => false;

  @override
  String get tabId => tab.id;

  @override
  String get workspaceId => workspace.id;

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return Center(key: key, child: Text('E2E terminal: ${tab.title}'));
  }

  @override
  Future<void> ensureStarted() async {
    if (_started) {
      return;
    }
    _started = true;
    notifyListeners();
  }

  @override
  void requestFocus() {}

  @override
  Future<void> restart() => ensureStarted();
}
