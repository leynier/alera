import 'workflow_cleanup_fixture.dart';

Map<String, Object?> cleanupResourcesFixture({
  int revision = 4,
  int? nextRow,
}) => {
  'runId': 'run',
  'revision': revision,
  'nextBeforeRow': nextRow,
  'items': [
    {
      'identity':
          ((cleanupPreviewFixture()['items']! as List).single
              as Map)['identity'],
      'phase': 'ready',
      'registered': true,
      'retired': false,
      'cleanupId': null,
      'cleanupState': null,
    },
  ],
};

Map<String, Object?> cleanupHistoryFixture({bool empty = false}) => {
  'runId': 'run',
  'revision': 4,
  'nextBeforeRow': null,
  'items': empty
      ? <Object>[]
      : [
          {
            'id': 'cleanup',
            'state': 'attention',
            'error': 'Inspect the retained worktree.',
            'resourceCount': 1,
            'retiredCount': 0,
          },
        ],
};
