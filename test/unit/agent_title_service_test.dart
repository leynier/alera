import 'package:alera/src/features/ai_assist/application/agent_title_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('title settings default on and preserve operation overrides', () {
    expect(
      AiAssistSettings.fromJson(<String, Object?>{}).autoGenerateAgentTitles,
      isTrue,
    );
    const settings = AiAssistSettings(
      autoGenerateAgentTitles: false,
      promptSettingsByOperation: {
        AiAssistOperation.agentTitle: AiAssistPromptSettings(
          agent: .pi,
          model: 'model',
        ),
      },
    );
    final decoded = AiAssistSettings.fromJson(settings.toMap());
    expect(decoded.autoGenerateAgentTitles, isFalse);
    expect(decoded.agentFor(.agentTitle), AiAssistAgent.pi);
    expect(decoded.modelForOperation(.agentTitle), 'model');
  });

  test(
    'generation sends identity preconditions without conversation content',
    () async {
      final client = _Client();
      final service = AgentTitleService(client);
      await service.generate(
        WorkspaceTabRecord(
          id: 'tab',
          workspaceId: 'workspace',
          kind: .terminal,
          title: 'My title',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          payload: const {
            'agentTitleConversationId': 'conversation',
            'agentTitleRevision': 'revision',
            'initialPrompt': 'private',
          },
        ),
      );
      expect(client.type, 'aiText.agentTitle.generate');
      expect(client.payload, {
        'tabId': 'tab',
        'expectedConversationId': 'conversation',
        'expectedRevision': 'revision',
      });
      expect(client.timeout, const Duration(minutes: 11));
    },
  );

  test('old hosts do not advertise generation actions', () async {
    final client = _Client();
    final service = AgentTitleService(client);
    expect(await service.isAvailable(), isFalse);
    client.response = {
      'runtimeCapabilities': [agentTitleCapability],
    };
    expect(await service.isAvailable(), isTrue);
  });
}

class _Client implements RuntimeHostClient {
  Object? response = const <String, Object?>{};
  String? type;
  Map<String, Object?>? payload;
  Duration? timeout;
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();
  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    this.type = type;
    this.payload = payload;
    this.timeout = timeout;
    return response;
  }
}
