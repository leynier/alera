import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/error_reporting/application/ai_error_clarifier.dart';
import 'package:alera/src/features/error_reporting/application/error_reporting_providers.dart';
import 'package:alera/src/features/error_reporting/presentation/action_failure_toast.dart';
import 'package:alera/src/features/error_reporting/presentation/error_notification_host.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  late List<LogRecord> records;

  setUp(() {
    records = <LogRecord>[];
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(() {
      subscription.cancel();
      Logger.root.level = previousLevel;
    });
  });

  testWidgets('logs every error and warning shown to the user', (tester) async {
    await _pumpHost(tester, aiAssist: const AiAssistSettings());

    AleraToast.publish(message: 'Push failed', tone: .error);
    AleraToast.publish(message: 'Setup warnings', tone: .warning);
    AleraToast.publish(message: 'Saved', tone: .success);
    await tester.pump();

    final visible = records
        .where((record) => record.loggerName == 'UserVisibleErrors')
        .toList();
    expect(visible.map((record) => (record.level, record.message)), [
      (Level.WARNING, 'Error shown to the user: Push failed'),
      (Level.INFO, 'Warning shown to the user: Setup warnings'),
    ]);

    await tester.pump(AleraTokens.toastLongDuration);
    await tester.pump(AleraTokens.durationMid);
  });

  testWidgets('wires the clarifier only while the setting is on', (
    tester,
  ) async {
    await _pumpHost(tester, aiAssist: const AiAssistSettings());
    expect(
      tester.widget<AleraToastHost>(find.byType(AleraToastHost)).clarifyError,
      isNull,
    );

    await _pumpHost(
      tester,
      aiAssist: const AiAssistSettings(
        enabled: false,
        clarifyErrorMessages: true,
      ),
    );
    expect(
      tester.widget<AleraToastHost>(find.byType(AleraToastHost)).clarifyError,
      isNull,
    );

    await _pumpHost(
      tester,
      aiAssist: const AiAssistSettings(clarifyErrorMessages: true),
    );
    final host = tester.widget<AleraToastHost>(find.byType(AleraToastHost));
    expect(host.clarifyError, isNotNull);
    expect(host.clarifyingCaption, 'Clarifying with AI Assist…');
    expect(host.clarifiedCaption, 'Clarified by AI Assist');
  });

  testWidgets('an action failure reaches the log and a clarified toast', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      aiAssist: const AiAssistSettings(clarifyErrorMessages: true),
    );

    showActionFailure(
      action: 'push branch',
      error: StateError('rejected: non-fast-forward'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('The push was rejected. Pull first.'), findsOneWidget);
    expect(find.text('Copy Original'), findsOneWidget);
    expect(
      records.where((record) => record.loggerName == 'UserActions').single,
      isA<LogRecord>()
          .having(
            (record) => record.message,
            'message',
            'Could not push branch',
          )
          .having((record) => record.error, 'error', isA<StateError>()),
    );
    expect(
      records
          .where((record) => record.loggerName == 'UserVisibleErrors')
          .single
          .message,
      'Error shown to the user: '
      'Could not push branch: Rejected: non-fast-forward',
    );

    await tester.pump(AleraTokens.toastLongDuration);
    await tester.pump(AleraTokens.durationMid);
  });
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required AiAssistSettings aiAssist,
}) {
  return tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        settingsControllerProvider.overrideWithValue(
          AleraSettings.defaults.copyWith(aiAssist: aiAssist),
        ),
        aiErrorClarifierProvider.overrideWithValue(
          AiErrorClarifier(
            runner: _FixedRunner(),
            readSettings: () => aiAssist,
          ),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(body: ErrorNotificationHost()),
      ),
    ),
  );
}

class _FixedRunner implements AgentTaskRunner {
  @override
  Future<AiAssistAgentRunResult> run(AiAssistAgentRunRequest request) async {
    return const AiAssistAgentRunResult(
      text: 'The push was rejected. Pull first.',
      agentLabel: 'Codex',
    );
  }

  @override
  void cancel(String runId) {}
}
