part of 'codex_chat_controller.dart';

extension CodexChatRequestResponses on CodexChatController {
  Future<void> respondApproval(
    CodexPendingRequest request, {
    required Object decision,
  }) async {
    try {
      final decisionName = request.approvalDecisionName(decision);
      final accepted =
          decisionName == 'accept' || decisionName == 'acceptForSession';
      final result = request.isPermissionsRequest
          ? <String, Object?>{
              'permissions': accepted
                  ? _permissionSubset(request.params['permissions'])
                  : const <String, Object?>{},
              'scope': decisionName == 'acceptForSession' ? 'session' : 'turn',
            }
          : <String, Object?>{
              'decision': request.approvalWireDecision(decision),
            };
      await _host.respond(request.id, result: result);
    } catch (error) {
      _recordRequestError(error);
    }
  }

  Future<void> respondQuestion(
    CodexPendingRequest request,
    Map<String, Object?> answers,
  ) async {
    try {
      await _host.respond(
        request.id,
        result: <String, Object?>{
          'answers': <String, Object?>{
            for (final entry in answers.entries)
              entry.key: <String, Object?>{'answers': entry.value},
          },
        },
      );
    } catch (error) {
      _recordRequestError(error);
    }
  }

  Future<void> snoozeQuestionAutoResolution(CodexPendingRequest request) async {
    if (request.isBlocking) return;
    try {
      await _host.snoozeRequest(request.id);
    } on Object {
      // Older runtime hosts do not expose the additive snooze request.
    }
  }

  Future<void> respondElicitation(
    CodexPendingRequest request, {
    required String action,
    Map<String, Object?> content = const <String, Object?>{},
  }) async {
    try {
      await _host.respond(
        request.id,
        result: <String, Object?>{
          'action': action,
          if (action == 'accept') 'content': content,
        },
      );
    } catch (error) {
      _recordRequestError(error);
    }
  }

  Future<void> rejectRequest(CodexPendingRequest request) async {
    try {
      await _host.respond(
        request.id,
        error: <String, Object?>{
          'code': -32601,
          'message': 'Alera does not support this Codex request.',
        },
      );
    } catch (error) {
      _recordRequestError(error);
    }
  }

  Future<void> submitQuestions(
    CodexPendingRequest request,
    Map<String, List<String>> answers,
  ) async {
    await respondQuestion(request, <String, Object?>{
      for (final entry in answers.entries) entry.key: entry.value,
    });
  }
}
