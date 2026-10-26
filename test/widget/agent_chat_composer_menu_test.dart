import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_file_search.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_menu.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_usage_popover.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const AgentChatComposerSettings _settings = AgentChatComposerSettings(
  provider: 'codex',
  providerInstanceId: 'codex',
  session: AgentChatSession(
    status: AgentChatSessionStatus.ready,
    capabilities: AgentChatCapabilities(plan: true),
  ),
  providers: <AgentChatProviderInstance>[],
  canSwitchProvider: true,
  configuring: false,
);

final class _Session implements AgentChatComposerFileSearchSession {
  _Session(this.files, this.error);

  final List<String> files;
  final Object? error;

  @override
  Future<List<String>> search(String query, {required int limit}) async {
    if (error case final Object error) throw error;
    return <String>[
      for (final file in files)
        if (file.toLowerCase().contains(query.toLowerCase())) file,
    ];
  }

  @override
  Future<void> close() async {}
}

final class _Files implements AgentChatComposerFileSearch {
  _Files(this.files, {this.error});

  final List<String> files;
  final Object? error;

  @override
  String get key => 'ws-1';

  @override
  Future<AgentChatComposerFileSearchSession> open() async =>
      _Session(files, error);

  @override
  String attachmentPath(String relativePath) => '/repo/$relativePath';
}

final class _Harness {
  final TerminalComposerController composer = TerminalComposerController();
  final AleraPopoverController picker = AleraPopoverController();
  final List<String> sent = <String>[];
  final List<AgentChatConfiguration> configured = <AgentChatConfiguration>[];
  int interrupts = 0;

  TextEditingController get text => composer.textController;

  Widget build({
    AgentChatComposerFileSearch? fileSearch,
    AgentChatUsage usage = const AgentChatUsage(),
    bool canInterrupt = false,
  }) => MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: AgentChatComposer(
          controller: composer,
          workspaceId: 'ws-1',
          chatId: 'chat-1',
          settings: _settings,
          usage: usage,
          canSend: true,
          busy: canInterrupt,
          canInterrupt: canInterrupt,
          interrupting: false,
          hintText: 'Message the agent',
          promptHistory: () => const <String>['older prompt'],
          pickerController: picker,
          fileSearch: fileSearch,
          onSend: (text, _, {steer = false}) {
            sent.add(text);
            return true;
          },
          onInterrupt: () => interrupts += 1,
          onConfigure: configured.add,
          onChoose: (_, _) {},
          onOpenFile: (_) {},
        ),
      ),
    ),
  );

  void dispose() {
    composer.dispose();
    picker.dispose();
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  AgentChatComposerFileSearch? fileSearch,
  AgentChatUsage usage = const AgentChatUsage(),
  bool canInterrupt = false,
}) async {
  final harness = _Harness();
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    harness.build(
      fileSearch: fileSearch,
      usage: usage,
      canInterrupt: canInterrupt,
    ),
  );
  await tester.tap(find.byType(TextField));
  await tester.pump();
  return harness;
}

/// Types [text] with the caret at its end and lets the debounced search run.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

final Finder _menu = find.byKey(
  const ValueKey<String>('agent-chat-composer-menu'),
);

void main() {
  testWidgets('@ lists workspace files and Enter attaches the active one', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      fileSearch: _Files(<String>[
        'lib/main.dart',
        'lib/app.dart',
        'README.md',
      ]),
    );

    await _type(tester, 'see @lib');
    expect(_menu, findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('app.dart'), findsOneWidget);
    expect(find.text('README.md'), findsNothing);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.enter);

    expect(harness.sent, isEmpty);
    expect(harness.text.text, 'see ');
    expect(
      harness.composer.attachments.map((attachment) => attachment.path),
      <String>['/repo/lib/app.dart'],
    );
    expect(_menu, findsNothing);
  });

  testWidgets('Tab and a click pick as well', (tester) async {
    final harness = await _pump(
      tester,
      fileSearch: _Files(<String>['lib/main.dart', 'README.md']),
    );

    await _type(tester, '@read');
    await _press(tester, LogicalKeyboardKey.tab);
    expect(harness.composer.attachments.single.path, '/repo/README.md');

    await _type(tester, '@main');
    await tester.tap(find.text('main.dart'));
    await tester.pump();
    expect(harness.composer.attachments.last.path, '/repo/lib/main.dart');
    expect(harness.text.text, isEmpty);
  });

  testWidgets('Escape closes the menu without stopping the turn', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      fileSearch: _Files(<String>['README.md']),
      canInterrupt: true,
    );

    await _type(tester, '@rea');
    expect(_menu, findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(_menu, findsNothing);
    expect(harness.interrupts, 0);
    expect(harness.text.text, '@rea');

    // The menu stays closed for the dismissed token...
    await _type(tester, '@read');
    expect(_menu, findsNothing);
    // ...and opens again for a new one.
    await _type(tester, '@read and @rea');
    expect(_menu, findsOneWidget);

    await _press(tester, LogicalKeyboardKey.escape);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(harness.interrupts, 1);
  });

  testWidgets('without a workspace the menu explains why it is empty', (
    tester,
  ) async {
    final harness = await _pump(tester);

    await _type(tester, '@src');
    expect(find.text(agentChatComposerNoFileSearchMessage), findsOneWidget);

    // Nothing to pick, so Enter still sends.
    await _press(tester, LogicalKeyboardKey.enter);
    expect(harness.sent, <String>['@src']);
  });

  testWidgets('a failed search shows the cause', (tester) async {
    await _pump(
      tester,
      fileSearch: _Files(const <String>[], error: StateError('index is gone')),
    );

    await _type(tester, '@src');
    expect(
      find.textContaining(
        RegExp(
          '^Could not search workspace files: index is gone',
          caseSensitive: false,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('/plan switches the interaction mode and clears the token', (
    tester,
  ) async {
    final harness = await _pump(tester);

    await _type(tester, '/');
    expect(find.text('/model'), findsOneWidget);
    expect(find.text('/plan'), findsOneWidget);
    expect(find.text('/default'), findsOneWidget);
    expect(find.text('/usage'), findsOneWidget);
    expect(find.text(agentChatSlashCommandDefaultActiveReason), findsOneWidget);
    expect(
      find.text(agentChatSlashCommandUsageUnavailableReason),
      findsOneWidget,
    );

    await _type(tester, '/pl');
    await _press(tester, LogicalKeyboardKey.enter);

    expect(harness.sent, isEmpty);
    expect(harness.text.text, isEmpty);
    expect(
      harness.configured.single.interactionMode,
      AgentChatInteractionMode.plan,
    );
  });

  testWidgets('a disabled command stays in the prompt on Enter', (
    tester,
  ) async {
    final harness = await _pump(tester);

    await _type(tester, '/default');
    await _press(tester, LogicalKeyboardKey.enter);

    expect(harness.configured, isEmpty);
    expect(harness.sent, isEmpty);
    expect(harness.text.text, '/default');
  });

  testWidgets('/model opens the model picker', (tester) async {
    final harness = await _pump(tester);

    await _type(tester, '/mo');
    await _press(tester, LogicalKeyboardKey.enter);

    expect(harness.picker.isOpen, isTrue);
    expect(harness.text.text, isEmpty);
  });

  testWidgets('/usage opens the usage popover', (tester) async {
    await _pump(
      tester,
      usage: const AgentChatUsage(contextTokens: 50, contextWindow: 100),
    );

    await _type(tester, '/us');
    await _press(tester, LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.byType(AgentChatUsageDetails), findsOneWidget);
  });

  testWidgets('a slash later in the prompt is plain text', (tester) async {
    final harness = await _pump(tester);

    await _type(tester, 'fix src/main');
    expect(_menu, findsNothing);
    await _type(tester, '/nothing-like-this');
    expect(find.text(agentChatComposerNoCommandsMessage), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.enter);
    expect(harness.sent, <String>['/nothing-like-this']);
  });

  testWidgets('the menu closes when the field loses focus', (tester) async {
    await _pump(tester, fileSearch: _Files(<String>['README.md']));

    await _type(tester, '@rea');
    expect(_menu, findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(_menu, findsNothing);
  });

  testWidgets('Up and Down move through the menu, not the history', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      fileSearch: _Files(<String>['a.dart', 'b.dart']),
    );

    await _type(tester, '@');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.text.text, '@');
    await _press(tester, LogicalKeyboardKey.enter);
    expect(harness.composer.attachments.single.path, '/repo/b.dart');
  });
}
