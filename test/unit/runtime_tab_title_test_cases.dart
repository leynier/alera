part of 'runtime_repositories_test.dart';

void _registerRuntimeTabTitleTests() {
  for (final source in ['generated', 'manual']) {
    test(
      'same-text $source title confirmation uses explicit runtime rename',
      () async {
        final client = _FakeRuntimeHostClient();
        final tab = <String, Object?>{
          'id': 'tab',
          'workspaceId': 'workspace',
          'kind': 'terminal',
          'title': 'Current Title',
          'createdAt': '2026-08-29T00:00:00Z',
          'updatedAt': '2026-08-29T00:00:00Z',
          'payload': <String, Object?>{
            'manualTitle': true,
            'agentTitleSource': source,
            'agentTitleStatus': 'generating',
            'agentTitleRevision': 'before',
          },
        };
        client.responses['tab.find'] = tab;
        client.responses['tab.rename'] = <String, Object?>{
          ...tab,
          'payload': <String, Object?>{
            'manualTitle': true,
            'agentTitleSource': 'manual',
            'agentTitleStatus': 'idle',
            'agentTitleRevision': 'after',
          },
        };
        final service = WorkspaceTabService(
          repository: RuntimeWorkbenchRepository(client),
        );
        final result = await service.renameTab(
          tabId: 'tab',
          title: ' Current Title ',
        );
        expect(client.requests, ['tab.find', 'tab.rename']);
        expect(client.payloads['tab.rename']!.single, {
          'id': 'tab',
          'title': 'Current Title',
        });
        expect(result.title, 'Current Title');
        expect(result.payload['agentTitleSource'], 'manual');
        expect(result.payload['agentTitleRevision'], 'after');
        expect(result.payload['agentTitleStatus'], 'idle');
      },
    );
  }
}
