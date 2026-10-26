import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/error_reporting/application/error_clarification_prompt.dart';
import 'package:alera/src/shared/infra/logging/log_redaction.dart';
import 'package:logging/logging.dart';

/// An error toast waits on the clarification, so it gets a much shorter
/// budget than a commit message does.
const Duration errorClarificationTimeout = Duration(seconds: 30);

const int _cacheCapacity = 32;

/// Rewrites an error message through AI Assist when the user turned on
/// Clarify Error Messages.
///
/// Every failure, timeout, or unusable answer returns null, and the caller
/// shows the original error. Nothing here may throw.
class AiErrorClarifier({
  required final AgentTaskRunner runner,
  required final AiAssistSettings Function() readSettings,
  final String? Function()? readWorkingDirectory,
  final Duration timeout = errorClarificationTimeout,
  Logger? logger,
}) {
  this : _logger = logger ?? Logger('ErrorClarification');

  final Logger _logger;
  final LinkedHashMap<String, String> _cache = LinkedHashMap<String, String>();
  var _sequence = 0;
  var _inFlight = false;

  bool get isEnabled {
    final settings = readSettings();
    return settings.enabled && settings.clarifyErrorMessages;
  }

  Future<String?> clarify(String message) async {
    final original = message.trim();
    if (original.isEmpty || !isEnabled) {
      return null;
    }
    final cached = _cache[original];
    if (cached != null) {
      return cached;
    }
    // One agent run at a time: a burst of errors must not start a burst of
    // agent processes. The errors that arrive meanwhile keep their original
    // text, which is the documented fallback.
    if (_inFlight) {
      return null;
    }
    _inFlight = true;
    final settings = readSettings();
    final runId = 'error-clarification-${++_sequence}';
    try {
      final result = await runner
          .run(
            AiAssistAgentRunRequest(
              settings: settings.copyWith(
                timeoutSeconds: math.min(
                  settings.timeoutSeconds,
                  timeout.inSeconds,
                ),
              ),
              prompt: buildErrorClarificationPrompt(redactLogText(original)),
              runId: runId,
              workingDirectory: readWorkingDirectory?.call(),
            ),
          )
          .timeout(
            timeout,
            onTimeout: () {
              runner.cancel(runId);
              throw TimeoutException('Error clarification timed out.', timeout);
            },
          );
      final clarified = parseErrorClarification(result.text);
      if (clarified == null || clarified == original) {
        return null;
      }
      _remember(original, clarified);
      return clarified;
    } on Object catch (error) {
      _logger.info('Error clarification failed; showing the original: $error');
      return null;
    } finally {
      _inFlight = false;
    }
  }

  void _remember(String original, String clarified) {
    _cache.remove(original);
    _cache[original] = clarified;
    while (_cache.length > _cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
  }
}
