import 'dart:async';

import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/error_reporting/application/ai_error_clarifier.dart';
import 'package:alera/src/features/error_reporting/application/error_clarification_prompt.dart';
import 'package:alera/src/shared/infra/logging/log_redaction.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const AiAssistSettings _enabled = AiAssistSettings(clarifyErrorMessages: true);

void main() {
  tearDown(resetRegisteredLogSecrets);

  group('buildErrorClarificationPrompt', () {
    test('wraps the trimmed error between the markers', () {
      final prompt = buildErrorClarificationPrompt('  Push rejected.  ');

      expect(prompt, contains('<<<\nPush rejected.\n>>>'));
      expect(prompt, contains('Reply with the rewritten message only'));
    });

    test('cuts an oversized error', () {
      final prompt = buildErrorClarificationPrompt(
        'x' * (errorClarificationInputLimit + 10),
      );

      expect(prompt, contains('[truncated: 10 characters omitted]'));
    });
  });

  group('parseErrorClarification', () {
    test('strips surrounding quotes', () {
      expect(
        parseErrorClarification('"The push was rejected."'),
        'The push was rejected.',
      );
      expect(
        parseErrorClarification("'The push was rejected.'"),
        'The push was rejected.',
      );
    });

    test('collapses a multiline answer into one paragraph', () {
      expect(
        parseErrorClarification(
          'The push was rejected.\n\n  Pull first, then push again.\n',
        ),
        'The push was rejected. Pull first, then push again.',
      );
    });

    test('rejects an empty answer', () {
      expect(parseErrorClarification(''), isNull);
      expect(parseErrorClarification('  \n '), isNull);
      expect(parseErrorClarification('""'), isNull);
    });

    test('rejects an answer that is too long', () {
      expect(
        parseErrorClarification('a' * (errorClarificationOutputLimit + 1)),
        isNull,
      );
      expect(
        parseErrorClarification('a' * errorClarificationOutputLimit),
        hasLength(errorClarificationOutputLimit),
      );
    });

    test('rejects an answer that echoes the prompt markers', () {
      expect(parseErrorClarification('<<< Push rejected. >>>'), isNull);
    });
  });

  group('AiErrorClarifier', () {
    test('does nothing while the setting is off', () async {
      for (final settings in const <AiAssistSettings>[
        AiAssistSettings(),
        AiAssistSettings(enabled: false, clarifyErrorMessages: true),
      ]) {
        final runner = _FakeRunner();
        final clarifier = AiErrorClarifier(
          runner: runner,
          readSettings: () => settings,
        );

        expect(clarifier.isEnabled, isFalse);
        expect(await clarifier.clarify('Push rejected.'), isNull);
        expect(runner.requests, isEmpty);
      }
    });

    test('skips an empty message without calling the runner', () async {
      final runner = _FakeRunner();
      final clarifier = AiErrorClarifier(
        runner: runner,
        readSettings: () => _enabled,
      );

      expect(await clarifier.clarify('   '), isNull);
      expect(runner.requests, isEmpty);
    });

    test('returns the parsed rewrite', () async {
      final runner = _FakeRunner()
        ..reply = (_) async => '"The push was rejected.\nPull first."';
      final clarifier = AiErrorClarifier(
        runner: runner,
        readSettings: () => _enabled,
        readWorkingDirectory: () => '/repo',
      );

      expect(
        await clarifier.clarify('  rejected: non-fast-forward  '),
        'The push was rejected. Pull first.',
      );
      final request = runner.requests.single;
      expect(request.prompt, contains('<<<\nrejected: non-fast-forward\n>>>'));
      expect(request.workingDirectory, '/repo');
      expect(request.runId, startsWith('error-clarification-'));
    });

    test('returns null when the runner throws', () async {
      final runner = _FakeRunner()
        ..reply = (_) async => throw StateError('Codex is not installed.');
      final clarifier = AiErrorClarifier(
        runner: runner,
        readSettings: () => _enabled,
      );

      expect(await clarifier.clarify('Push rejected.'), isNull);
    });

    test('returns null and cancels the run when it times out', () {
      fakeAsync((async) {
        final runner = _FakeRunner()..reply = (_) => Completer<String>().future;
        final clarifier = AiErrorClarifier(
          runner: runner,
          readSettings: () => _enabled,
          timeout: const Duration(seconds: 5),
        );
        String? result = 'unset';
        var done = false;
        unawaited(
          clarifier.clarify('Push rejected.').then((value) {
            result = value;
            done = true;
          }),
        );

        async.elapse(const Duration(seconds: 4));
        expect(done, isFalse);
        async.elapse(const Duration(seconds: 2));

        expect(done, isTrue);
        expect(result, isNull);
        expect(runner.cancelled, <String>[runner.requests.single.runId]);
      });
    });

    test('runs one clarification at a time', () async {
      final pending = Completer<String>();
      final runner = _FakeRunner()..reply = (_) => pending.future;
      final clarifier = AiErrorClarifier(
        runner: runner,
        readSettings: () => _enabled,
      );

      final first = clarifier.clarify('First error.');
      expect(await clarifier.clarify('Second error.'), isNull);
      pending.complete('The first error, clarified.');

      expect(await first, 'The first error, clarified.');
      expect(runner.requests, hasLength(1));

      runner.reply = (_) async => 'The second error, clarified.';
      expect(
        await clarifier.clarify('Second error.'),
        'The second error, clarified.',
      );
    });

    test('answers a repeated error from the cache', () async {
      final runner = _FakeRunner()..reply = (_) async => 'Clarified.';
      final clarifier = AiErrorClarifier(
        runner: runner,
        readSettings: () => _enabled,
      );

      expect(await clarifier.clarify('Push rejected.'), 'Clarified.');
      expect(await clarifier.clarify(' Push rejected. '), 'Clarified.');
      expect(runner.requests, hasLength(1));
    });

    test('returns null when the answer is unchanged or unusable', () async {
      final runner = _FakeRunner()..reply = (_) async => 'Push rejected.';
      final clarifier = AiErrorClarifier(
        runner: runner,
        readSettings: () => _enabled,
      );

      expect(await clarifier.clarify('Push rejected.'), isNull);
      runner.reply = (_) async => '   ';
      expect(await clarifier.clarify('Push rejected.'), isNull);
      expect(runner.requests, hasLength(2));
    });

    test('redacts registered secrets from the prompt', () async {
      const secret = 'ghp_supersecretvalue123';
      registerLogSecret(secret);
      final runner = _FakeRunner()..reply = (_) async => 'Clarified.';
      final clarifier = AiErrorClarifier(
        runner: runner,
        readSettings: () => _enabled,
      );

      await clarifier.clarify('Clone failed for https://$secret@github.com/x');

      final prompt = runner.requests.single.prompt;
      expect(prompt, isNot(contains(secret)));
      expect(prompt, contains(kRedactedPlaceholder));
    });

    test('caps the agent timeout to the clarification budget', () async {
      final runner = _FakeRunner()..reply = (_) async => 'Clarified.';
      final clarifier = AiErrorClarifier(
        runner: runner,
        readSettings: () => const AiAssistSettings(
          clarifyErrorMessages: true,
          timeoutSeconds: 600,
        ),
      );

      await clarifier.clarify('Push rejected.');
      expect(
        runner.requests.single.settings.timeoutSeconds,
        errorClarificationTimeout.inSeconds,
      );

      final shortRunner = _FakeRunner()..reply = (_) async => 'Clarified.';
      final shortClarifier = AiErrorClarifier(
        runner: shortRunner,
        readSettings: () => const AiAssistSettings(
          clarifyErrorMessages: true,
          timeoutSeconds: 10,
        ),
      );
      await shortClarifier.clarify('Push rejected.');
      expect(shortRunner.requests.single.settings.timeoutSeconds, 10);
    });
  });
}

class _FakeRunner implements AgentTaskRunner {
  final List<AiAssistAgentRunRequest> requests = <AiAssistAgentRunRequest>[];
  final List<String> cancelled = <String>[];
  Future<String> Function(AiAssistAgentRunRequest request) reply = (_) async =>
      'Clarified.';

  @override
  Future<AiAssistAgentRunResult> run(AiAssistAgentRunRequest request) async {
    requests.add(request);
    final text = await reply(request);
    return AiAssistAgentRunResult(text: text, agentLabel: 'Codex');
  }

  @override
  void cancel(String runId) => cancelled.add(runId);
}
