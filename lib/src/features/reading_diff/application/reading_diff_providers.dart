import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_service.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reading_diff_providers.g.dart';

@Riverpod(keepAlive: true)
ReadingDiffService readingDiffService(Ref ref) {
  return ReadingDiffService(
    gitBackend: ref.read(gitBackendProvider),
    runner: ref.read(aiAssistAgentRunnerProvider),
  );
}
