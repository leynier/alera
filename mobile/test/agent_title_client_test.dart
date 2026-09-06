import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_workspace_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'generation is negotiated and carries only identity preconditions',
    () async {
      final client = _Client();
      expect(client.supportsAgentTitles, isFalse);
      client.runtimeCapabilities.add(aiAssistAgentTitleCapability);
      expect(client.supportsAgentTitles, isTrue);
      await client.generateAgentTitle(
        const WorkspaceTabSummary(
          id: 'tab',
          workspaceId: 'workspace',
          kind: 'terminal',
          title: 'Title',
          payload: {
            'agentTitleConversationId': 'conversation',
            'agentTitleRevision': 'revision',
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

  test('generated titles override OSC generic labels', () {
    final tab = WorkspaceTabSummary(
      id: 'tab',
      workspaceId: 'workspace',
      kind: 'terminal',
      title: 'Fix Login With Google',
      runtimeTitle: 'bash',
      payload: const {'manualTitle': true, 'agentTitleSource': 'generated'},
    );
    expect(tab.displayTitle, 'Fix Login With Google');
  });
}

class _Client with MobileRuntimeWorkspaceClient {
  @override
  final Set<String> runtimeCapabilities = {};
  String? type;
  Map<String, Object?>? payload;
  Duration? timeout;
  @override
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    this.type = type;
    this.payload = payload;
    this.timeout = timeout;
    return const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async => const {};
  @override
  Future<List<Object?>> requestList(
    String type, [
    Map<String, Object?> payload = const {},
  ]) async => const [];
}
