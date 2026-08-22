import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profile_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('managed mode shows agent-specific controls and preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      _EditorHarness(
        launchMode: AgentProfileLaunchMode.managed,
        managedConfig: const <String, Object?>{
          'model': 'gpt-5.6-sol',
          'webSearch': true,
        },
      ),
    );

    expect(find.text('Managed Options'), findsOneWidget);
    expect(find.text('Reasoning Effort'), findsOneWidget);
    expect(find.text('Approval Policy'), findsOneWidget);
    expect(find.textContaining('gpt-5.6-sol'), findsWidgets);
    expect(find.text('Command'), findsNothing);
  });

  testWidgets('Codex exposes a plan mode effort it cannot start in', (
    tester,
  ) async {
    await tester.pumpWidget(
      _EditorHarness(
        launchMode: AgentProfileLaunchMode.managed,
        managedConfig: const <String, Object?>{'planModeEffort': 'xhigh'},
      ),
    );

    expect(find.text('Plan Mode Reasoning Effort'), findsOneWidget);
    expect(find.textContaining('Shift+Tab or /plan'), findsOneWidget);
    expect(
      find.text('codex --config plan_mode_reasoning_effort=xhigh'),
      findsOneWidget,
    );
  });

  testWidgets('command mode keeps the advanced raw command field', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _EditorHarness(launchMode: AgentProfileLaunchMode.command),
    );

    expect(find.text('Command'), findsWidgets);
    expect(find.text('Managed Options'), findsNothing);
    expect(find.textContaining('Command mode is for advanced'), findsOneWidget);
  });

  testWidgets('command mode explains where the dispatched prompt goes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _EditorHarness(launchMode: AgentProfileLaunchMode.command),
    );

    expect(find.text('Prompt Delivery'), findsOneWidget);
    expect(find.text('Custom Prompt'), findsOneWidget);
    expect(
      find.textContaining('appends the dispatched prompt'),
      findsOneWidget,
    );
    expect(find.text("codex -- 'Dispatched Prompt'"), findsOneWidget);
  });

  testWidgets('command mode offers to test the current command', (
    tester,
  ) async {
    var testCommandCalls = 0;
    await tester.pumpWidget(
      _EditorHarness(
        launchMode: AgentProfileLaunchMode.command,
        onTestCommand: () => testCommandCalls++,
      ),
    );

    await tester.tap(find.text('Test Command'));
    await tester.pump();

    expect(testCommandCalls, 1);
  });

  testWidgets('command mode gives the test button room inside its card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _EditorHarness(launchMode: AgentProfileLaunchMode.command),
    );

    final actionPadding = _testCommandActionPadding(tester);

    expect(
      actionPadding.resolve(TextDirection.ltr).bottom,
      AleraTokens.space12,
    );
  });

  testWidgets('managed mode offers to test the current command preview', (
    tester,
  ) async {
    var testCommandCalls = 0;
    await tester.pumpWidget(
      _EditorHarness(
        launchMode: AgentProfileLaunchMode.managed,
        managedConfig: const <String, Object?>{'model': 'gpt-5.6-sol'},
        onTestCommand: () => testCommandCalls++,
      ),
    );

    await tester.tap(find.text('Test Command'));
    await tester.pump();

    expect(testCommandCalls, 1);
  });

  testWidgets('managed mode gives the test button room inside its card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _EditorHarness(
        launchMode: AgentProfileLaunchMode.managed,
        managedConfig: const <String, Object?>{'model': 'gpt-5.6-sol'},
      ),
    );

    final actionPadding = _testCommandActionPadding(tester);

    expect(
      actionPadding.resolve(TextDirection.ltr).bottom,
      AleraTokens.space12,
    );
  });

  testWidgets('managed mode disables testing while saving', (tester) async {
    var testCommandCalls = 0;
    await tester.pumpWidget(
      _EditorHarness(
        launchMode: AgentProfileLaunchMode.managed,
        managedConfig: const <String, Object?>{'model': 'gpt-5.6-sol'},
        saving: true,
        onTestCommand: () => testCommandCalls++,
      ),
    );

    final testButton = find.widgetWithText(OutlinedButton, 'Test Command');
    expect(tester.widget<OutlinedButton>(testButton).onPressed, isNull);
    expect(testCommandCalls, 0);
  });

  testWidgets('a Claude managed profile can route through a CCS profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _EditorHarness(
        adapter: AgentType.claude,
        launchMode: AgentProfileLaunchMode.managed,
        managedConfig: const <String, Object?>{
          'ccsProfile': 'work',
          'model': 'opus',
        },
      ),
    );

    expect(find.text('CCS Profile'), findsOneWidget);
    expect(find.text('ccs work --model opus'), findsOneWidget);
  });

  testWidgets(
    'a Claude managed profile can allow bypass without starting in it',
    (tester) async {
      await tester.pumpWidget(
        _EditorHarness(
          adapter: AgentType.claude,
          launchMode: AgentProfileLaunchMode.managed,
          managedConfig: const <String, Object?>{
            'permissionMode': 'plan',
            'allowSkipPermissions': true,
          },
        ),
      );

      expect(find.text('Allow Skip Permissions'), findsOneWidget);
      expect(
        find.text(
          'claude --permission-mode plan '
          '--allow-dangerously-skip-permissions',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('only the Claude adapter offers a CCS profile', (tester) async {
    await tester.pumpWidget(
      const _EditorHarness(launchMode: AgentProfileLaunchMode.managed),
    );

    expect(find.text('CCS Profile'), findsNothing);
  });

  testWidgets('managed Grok Build exposes permission, sandbox, and effort', (
    tester,
  ) async {
    await tester.pumpWidget(
      _EditorHarness(
        adapter: AgentType.grok,
        launchMode: AgentProfileLaunchMode.managed,
        managedConfig: const <String, Object?>{
          'model': 'grok-4.6',
          'effort': 'high',
          'permissionMode': 'acceptEdits',
          'sandbox': 'workspace',
        },
      ),
    );

    expect(find.text('Managed Options'), findsOneWidget);
    expect(find.text('Persona'), findsOneWidget);
    expect(find.text('Reasoning Effort'), findsOneWidget);
    expect(find.text('Permission Mode'), findsOneWidget);
    expect(find.text('Sandbox'), findsOneWidget);
    expect(find.text('Disable Web Search'), findsOneWidget);
    expect(
      find.text(
        'grok --model grok-4.6 --effort high --permission-mode acceptEdits --sandbox workspace',
      ),
      findsOneWidget,
    );
  });

  testWidgets('managed mode surfaces reduced protection warnings', (
    tester,
  ) async {
    await tester.pumpWidget(
      _EditorHarness(
        launchMode: AgentProfileLaunchMode.managed,
        managedConfig: const <String, Object?>{
          'bypassApprovalsAndSandbox': true,
        },
      ),
    );

    expect(
      find.textContaining('bypass Codex approvals and sandbox protections'),
      findsOneWidget,
    );
  });
}

EdgeInsetsGeometry _testCommandActionPadding(WidgetTester tester) {
  final button = find.widgetWithText(OutlinedButton, 'Test Command');
  final buttonElement = tester.element(button);
  return buttonElement.findAncestorWidgetOfExactType<Padding>()!.padding;
}

class _EditorHarness extends StatefulWidget {
  const _EditorHarness({
    required this.launchMode,
    this.adapter = AgentType.codex,
    this.managedConfig = const <String, Object?>{},
    this.saving = false,
    this.onTestCommand,
  });

  final AgentProfileLaunchMode launchMode;
  final AgentType adapter;
  final Map<String, Object?> managedConfig;
  final bool saving;
  final VoidCallback? onTestCommand;

  @override
  State<_EditorHarness> createState() => _EditorHarnessState();
}

class _EditorHarnessState extends State<_EditorHarness> {
  late final TextEditingController _nameController;
  late final TextEditingController _commandController;
  late final TextEditingController _customPromptController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _quotaGroupController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Codex');
    _commandController = TextEditingController(text: 'codex');
    _customPromptController = TextEditingController();
    _descriptionController = TextEditingController();
    _quotaGroupController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _customPromptController.dispose();
    _descriptionController.dispose();
    _quotaGroupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 900,
          child: AgentProfileEditor(
            nameController: _nameController,
            commandController: _commandController,
            customPromptController: _customPromptController,
            descriptionController: _descriptionController,
            quotaGroupController: _quotaGroupController,
            adapter: widget.adapter,
            launchMode: widget.launchMode,
            managedConfig: widget.managedConfig,
            models: const <ManagedAgentOption>[
              ManagedAgentOption('gpt-5.6-sol', 'GPT-5.6 Sol'),
            ],
            personas: const <ManagedAgentOption>[],
            hasSelection: true,
            saving: widget.saving,
            onAdapterChanged: (_) {},
            onLaunchModeChanged: (_) {},
            onManagedConfigChanged: (_) {},
            onRefreshModels: null,
            onRefreshPersonas: null,
            onSave: () {},
            onRemove: () {},
            onTestCommand: widget.onTestCommand,
          ),
        ),
      ),
    );
  }
}
