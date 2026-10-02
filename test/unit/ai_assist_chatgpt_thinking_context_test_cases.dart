part of 'ai_assist_service_test.dart';

void _registerChatGptThinkingContextTests() {
  test(
    'ChatGPT sends saved thinking context when the account model is unresolved',
    () async {
      final chatgpt = _FakeOpenCodeGoCompleter(text: 'feat: connected');
      final runner = CliAiAssistAgentRunner(
        processRunner: _FakeProcessRunner(stdout: 'should-not-run'),
        chatGptCompleter: chatgpt,
      );

      await runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(
            agent: AiAssistAgent.chatgpt,
            selectedThinkingByModel: <String, String>{'gpt-6.1-sol': 'high'},
            selectedThinkingByOperation:
                <AiAssistOperation, Map<String, String>>{
                  AiAssistOperation.commitMessage: <String, String>{
                    'gpt-6.1-sol': 'xhigh',
                  },
                },
          ),
          prompt: 'Summarize this diff',
          runId: 'chatgpt-cold-catalog',
          workingDirectory: '/repo',
          agent: AiAssistAgent.chatgpt,
          model: '',
          operation: AiAssistOperation.commitMessage,
        ),
      );

      expect(chatgpt.lastModel, isEmpty);
      expect(chatgpt.lastThinkingLevel, isNull);
      expect(chatgpt.lastServiceTier, aiAssistChatGptDefaultServiceTier);
      expect(
        chatgpt.lastThinkingContext?.operation,
        AiAssistOperation.commitMessage,
      );
      expect(
        chatgpt.lastThinkingContext?.selectedThinkingByModel,
        <String, String>{'gpt-6.1-sol': 'high'},
      );
      expect(
        chatgpt.lastThinkingContext?.selectedThinkingByOperation,
        <String, String>{'gpt-6.1-sol': 'xhigh'},
      );
    },
  );

  test(
    'ChatGPT sends global thinking context for a generic unresolved request',
    () async {
      final chatgpt = _FakeOpenCodeGoCompleter(text: 'feat: connected');
      final runner = CliAiAssistAgentRunner(
        processRunner: _FakeProcessRunner(stdout: 'should-not-run'),
        chatGptCompleter: chatgpt,
      );

      await runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(
            agent: AiAssistAgent.chatgpt,
            selectedThinkingByModel: <String, String>{'gpt-6.1-sol': 'high'},
          ),
          prompt: 'Rewrite this selection',
          runId: 'chatgpt-generic-cold-catalog',
          workingDirectory: '/repo',
          agent: AiAssistAgent.chatgpt,
          model: '',
        ),
      );

      expect(chatgpt.lastThinkingLevel, isNull);
      expect(chatgpt.lastThinkingContext?.operation, isNull);
      expect(
        chatgpt.lastThinkingContext?.selectedThinkingByModel,
        <String, String>{'gpt-6.1-sol': 'high'},
      );
      expect(chatgpt.lastThinkingContext?.selectedThinkingByOperation, isEmpty);
    },
  );

  test(
    'ChatGPT does not add context for a cold catalog without saved thinking',
    () async {
      final chatgpt = _FakeOpenCodeGoCompleter(text: 'feat: connected');
      final runner = CliAiAssistAgentRunner(
        processRunner: _FakeProcessRunner(stdout: 'should-not-run'),
        chatGptCompleter: chatgpt,
      );

      await runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(agent: AiAssistAgent.chatgpt),
          prompt: 'Rewrite this selection',
          runId: 'chatgpt-cold-catalog-default',
          workingDirectory: '/repo',
          agent: AiAssistAgent.chatgpt,
          model: '',
        ),
      );

      expect(chatgpt.lastThinkingLevel, isNull);
      expect(chatgpt.lastServiceTier, aiAssistChatGptDefaultServiceTier);
      expect(chatgpt.lastThinkingContext, isNull);
    },
  );

  test(
    'ChatGPT context is rejected by an older host even without an effort',
    () async {
      final client = _ChatGptRuntimeHostClient(
        capabilities: <String>{aleraRuntimeHostAiAssistChatGptCapability},
        responses: <String, Object?>{
          'aiAssist.complete': <String, Object?>{
            'text': 'should-not-run',
            'agentLabel': 'ChatGPT',
          },
        },
      );

      await expectLater(
        RuntimeHostAiAssistCompleter(
          client: client,
          agent: AiAssistAgent.chatgpt,
        ).complete(
          prompt: 'text',
          model: '',
          sessionId: 'session',
          operationId: 'operation-context',
          timeoutSeconds: 30,
          serviceTier: aiAssistChatGptDefaultServiceTier,
          thinkingContext: const AiAssistThinkingContext(
            selectedThinkingByModel: <String, String>{'gpt-6.1-sol': 'high'},
            selectedThinkingByOperation: <String, String>{},
          ),
        ),
        throwsA(
          isA<AiAssistException>().having(
            (error) => error.message,
            'message',
            chatGptOptionsHostTooOldMessage,
          ),
        ),
      );
      expect(client.requestedTypes, isNot(contains('aiAssist.complete')));
    },
  );
}
