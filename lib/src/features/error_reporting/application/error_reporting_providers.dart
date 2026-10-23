import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/error_reporting/application/ai_error_clarifier.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'error_reporting_providers.g.dart';

@Riverpod(keepAlive: true)
AiErrorClarifier aiErrorClarifier(Ref ref) {
  return AiErrorClarifier(
    runner: ref.read(aiAssistAgentRunnerProvider),
    readSettings: () => ref.read(settingsControllerProvider).aiAssist,
    readWorkingDirectory: () =>
        ref.read(workbenchControllerProvider).activeWorkspace?.path,
  );
}
