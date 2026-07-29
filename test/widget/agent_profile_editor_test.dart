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

  testWidgets('command mode keeps the advanced raw command field', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _EditorHarness(launchMode: AgentProfileLaunchMode.command),
    );

    expect(find.text('Command'), findsWidgets);
    expect(find.text('Managed Options'), findsNothing);
    expect(find.textContaining('Command Mode Is For Advanced'), findsOneWidget);
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
      find.textContaining('Bypass Codex Approvals And Sandbox Protections'),
      findsOneWidget,
    );
  });
}

class _EditorHarness extends StatefulWidget {
  const _EditorHarness({
    required this.launchMode,
    this.managedConfig = const <String, Object?>{},
  });

  final AgentProfileLaunchMode launchMode;
  final Map<String, Object?> managedConfig;

  @override
  State<_EditorHarness> createState() => _EditorHarnessState();
}

class _EditorHarnessState extends State<_EditorHarness> {
  late final TextEditingController _nameController;
  late final TextEditingController _commandController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _quotaGroupController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Codex');
    _commandController = TextEditingController(text: 'codex');
    _descriptionController = TextEditingController();
    _quotaGroupController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
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
            descriptionController: _descriptionController,
            quotaGroupController: _quotaGroupController,
            adapter: AgentType.codex,
            launchMode: widget.launchMode,
            managedConfig: widget.managedConfig,
            models: const <ManagedAgentOption>[
              ManagedAgentOption('gpt-5.6-sol', 'GPT-5.6 Sol'),
            ],
            personas: const <ManagedAgentOption>[],
            hasSelection: true,
            saving: false,
            onAdapterChanged: (_) {},
            onLaunchModeChanged: (_) {},
            onManagedConfigChanged: (_) {},
            onRefreshModels: null,
            onRefreshPersonas: null,
            onSave: () {},
            onRemove: () {},
          ),
        ),
      ),
    );
  }
}
