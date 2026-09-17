import 'dart:async';

import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/agent_profile_launch_sheet.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_attachment_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_image_picker.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

void main() {
  testWidgets('skip launches the profile without a prompt', (tester) async {
    final launched = <String>[];
    await _pumpSheet(
      tester,
      onLaunch: ({required prompt}) async => launched.add(prompt),
    );

    expect(find.text('Start Shown Codex'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(launched, ['']);
    expect(find.byType(AgentProfileLaunchSheet), findsNothing);
  });

  testWidgets('programmatic prompt updates enable start agent', (tester) async {
    final launched = <String>[];
    await _pumpSheet(
      tester,
      onLaunch: ({required prompt}) async => launched.add(prompt),
    );

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    tester
        .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
        .controller!
        .value = const TextEditingValue(
      text: 'Dictated task',
    );
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Start Agent'));
    await tester.pumpAndSettle();

    expect(launched, ['Dictated task']);
  });

  testWidgets('start agent sends the typed prompt', (tester) async {
    final launched = <String>[];
    await _pumpSheet(
      tester,
      onLaunch: ({required prompt}) async => launched.add(prompt),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Review the composer',
    );
    await tester.pump();
    await tester.tap(find.text('Start Agent'));
    await tester.pumpAndSettle();

    expect(launched, ['Review the composer']);
    expect(find.byType(AgentProfileLaunchSheet), findsNothing);
  });

  testWidgets('Control+Enter starts the agent from the prompt field', (
    tester,
  ) async {
    final launched = <String>[];
    await _pumpSheet(
      tester,
      onLaunch: ({required prompt}) async => launched.add(prompt),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Review the composer',
    );
    await tester.pump();
    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyEvent(.enter);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    expect(launched, ['Review the composer']);
    expect(find.byType(AgentProfileLaunchSheet), findsNothing);
  });

  testWidgets('close dismisses without launching', (tester) async {
    final launched = <String>[];
    await _pumpSheet(
      tester,
      onLaunch: ({required prompt}) async => launched.add(prompt),
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(find.byType(AgentProfileLaunchSheet), findsNothing);
  });

  testWidgets('launch errors stay in the dialog', (tester) async {
    await _pumpSheet(
      tester,
      onLaunch: ({required prompt}) async {
        throw Exception('host refused the launch');
      },
    );

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('host refused the launch'), findsOneWidget);
    expect(find.byType(AgentProfileLaunchSheet), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('hides Add Attachment when the host offers no source', (
    tester,
  ) async {
    final client = FakeTerminalClient()..supportsPromptImageUpload = false;
    addTearDown(client.dispose);
    await _pumpSheet(
      tester,
      client: client,
      onLaunch: ({required prompt}) async {},
    );

    expect(find.text('Add Attachment'), findsNothing);
  });

  testWidgets('inserts an uploaded image path into the prompt', (tester) async {
    final launched = <String>[];
    final client = FakeTerminalClient();
    final picker = _FakePromptImagePicker(<PromptImageFile>[
      PromptImageFile(
        name: 'shot.png',
        sizeBytes: 8,
        openRead: () => Stream<List<int>>.value(List<int>.filled(8, 1)),
      ),
    ]);
    addTearDown(client.dispose);
    await _pumpSheet(
      tester,
      client: client,
      imagePicker: picker,
      onLaunch: ({required prompt}) async => launched.add(prompt),
    );

    await tester.tap(find.text('Add Attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo Library'));
    await tester.pumpAndSettle();

    final prompt = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
        .controller!;
    expect(prompt.text, '/runtime/prompt-images/upload-1.png');

    await tester.tap(find.text('Start Agent'));
    await tester.pumpAndSettle();
    expect(launched, ['/runtime/prompt-images/upload-1.png']);
  });

  testWidgets('new tab skip launches an empty prompt and selects the tab', (
    tester,
  ) async {
    final client = await _pumpTabs(tester);
    addTearDown(client.dispose);

    await tester.tap(find.byTooltip('New Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shown Codex'));
    await tester.pumpAndSettle();

    expect(find.text('Start Shown Codex'), findsOneWidget);
    expect(
      client.calls.where((call) => call.startsWith('launchAgentProfile')),
      isEmpty,
    );

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where(
        (call) =>
            call.startsWith('launchAgentProfile workspace-1 profile-shown'),
      ),
      ['launchAgentProfile workspace-1 profile-shown '],
    );
    expect(
      tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'profile-shown'))
          .selected,
      isTrue,
    );
  });

  testWidgets('new tab start agent sends the prompt and selects the tab', (
    tester,
  ) async {
    final client = await _pumpTabs(tester);
    addTearDown(client.dispose);

    await tester.tap(find.byTooltip('New Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shown Codex'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Fix the composer',
    );
    await tester.pump();
    await tester.tap(find.text('Start Agent'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where(
        (call) =>
            call.startsWith('launchAgentProfile workspace-1 profile-shown'),
      ),
      ['launchAgentProfile workspace-1 profile-shown Fix the composer'],
    );
    expect(
      tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'profile-shown'))
          .selected,
      isTrue,
    );
  });

  testWidgets('new tab close does not launch a profile', (tester) async {
    final client = await _pumpTabs(tester);
    addTearDown(client.dispose);

    await tester.tap(find.byTooltip('New Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shown Codex'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.startsWith('launchAgentProfile')),
      isEmpty,
    );
    expect(find.text('Start Shown Codex'), findsNothing);
  });
}

const _profile = AgentProfileSummary(
  id: 'profile-shown',
  name: 'Shown Codex',
  agentType: 'codex',
  showInNewTabMenu: true,
);

Future<void> _pumpSheet(
  WidgetTester tester, {
  required Future<void> Function({required String prompt}) onLaunch,
  FakeTerminalClient? client,
  PromptImagePicker? imagePicker,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final host = client ?? FakeTerminalClient();
  if (client == null) {
    addTearDown(host.dispose);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => host),
        terminalClientProvider('host-1').overrideWith((ref) async => host),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          () => FakeMobileAiDictationSettingsController(),
        ),
        if (imagePicker != null)
          promptImagePickerProvider.overrideWithValue(imagePicker),
      ],
      child: MaterialApp(
        home: AgentProfileLaunchSheet(
          profile: _profile,
          hostId: 'host-1',
          workspaceId: 'workspace-1',
          onLaunch: onLaunch,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<FakeTerminalClient> _pumpTabs(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = FakeTerminalClient()
    ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
    ..agentProfiles = const <AgentProfileSummary>[_profile];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          () => FakeMobileAiDictationSettingsController(),
        ),
      ],
      child: const MaterialApp(
        home: WorkspaceTabsScreen(
          hostId: 'host-1',
          workspace: WorkspaceSummary(
            id: 'workspace-1',
            projectId: 'project-1',
            name: 'Workspace',
            path: '/repo',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

class _FakePromptImagePicker(final List<PromptImageFile> images)
    implements PromptImagePicker {
  @override
  Future<List<PromptImageFile>> pickImages() async => images;
}
