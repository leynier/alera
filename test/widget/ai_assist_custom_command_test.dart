import 'dart:async';

import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/runtime_settings_repository.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_assist_custom_command_dialog.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_assist_pane.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final operation in <AiAssistOperation?>[
    null,
    AiAssistOperation.commitMessage,
  ]) {
    testWidgets('configures custom command atomically for $operation', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = _LegacyRuntimeClient();
      final cache = _MemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            RuntimeSettingsRepository(client: client, legacyRepository: cache),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.notifier).load();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAleraDarkTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Consumer(
                  builder: (context, ref, _) => AiAssistSettingsPane(
                    settings: ref.watch(settingsControllerProvider).aiAssist,
                    onChanged: (value) => unawaited(
                      ref
                          .read(settingsControllerProvider.notifier)
                          .updateAiAssist(value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selector = find.byKey(
        ValueKey<String>(
          operation == null
              ? 'ai-assist-agent-codex'
              : 'ai-assist-${operation.key}-agent-global',
        ),
      );
      Future<void> selectCustom() async {
        await tester.ensureVisible(selector);
        await tester.pumpAndSettle();
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Custom Command').last);
        await tester.pumpAndSettle();
      }

      await selectCustom();
      expect(find.byType(AiAssistCustomCommandDialog), findsOneWidget);
      expect(client.updates, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(client.updates, isEmpty);
      expect(
        container.read(settingsControllerProvider).aiAssist.agent,
        AiAssistAgent.codex,
      );

      await selectCustom();
      final input = find.descendant(
        of: find.byType(AiAssistCustomCommandDialog),
        matching: find.byType(AleraTextField),
      );
      await tester.enterText(input, '   ');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use Custom Command'),
            )
            .onPressed,
        isNull,
      );
      const command = 'llm --prompt {prompt}';
      await tester.enterText(input, command);
      await tester.pump();
      await tester.tap(find.text('Use Custom Command'));
      await tester.pumpAndSettle();
      expect(client.updates, hasLength(1));
      expect(client.updates.single['customCommand'], command);
      expect(
        container.read(settingsControllerProvider).aiAssist.customCommand,
        isEmpty,
      );
      expect(cache.settings.aiAssist.customCommand, isEmpty);
      client.persisted.complete();
      await tester.pumpAndSettle();
      final saved = container.read(settingsControllerProvider).aiAssist;
      expect(saved.customCommand, command);
      expect(
        operation == null ? saved.agent : saved.agentFor(operation),
        AiAssistAgent.custom,
      );
      expect(cache.settings.aiAssist, saved);
      expect(tester.takeException(), isNull);
    });
  }
}

class _MemorySettingsRepository implements SettingsRepository {
  var settings = AleraSettings.defaults.copyWith(
    aiAssist: AleraSettings.defaults.aiAssist.copyWith(enabled: false),
  );
  @override
  Future<AleraSettings> load() async => settings;
  @override
  Future<void> save(AleraSettings value) async => settings = value;
}

// The pre-sync runtime still rejects a custom agent without a command.
class _LegacyRuntimeClient implements RuntimeHostClient {
  final updates = <Map<String, Object?>>[];
  final persisted = Completer<void>();

  @override
  Future<Object?> runtimeRequest(
    String method, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    if (method == 'runtimeSettings.get') return <String, Object?>{};
    if (method != 'runtimeSettings.update') throw StateError(method);
    final settings = payload['aiTextGeneration']! as Map<String, Object?>;
    final ai = AiAssistSettings.fromJson(settings);
    final custom =
        ai.agent == AiAssistAgent.custom ||
        ai.promptSettingsByOperation.values.any(
          (prompt) => prompt.agent == AiAssistAgent.custom,
        );
    if (custom && ai.customCommand.trim().isEmpty) {
      throw StateError('Custom command is required');
    }
    updates.add(settings);
    await persisted.future;
    return <String, Object?>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
