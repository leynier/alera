Map<String, Object?> cleanupPreviewFixture({
  bool dirty = false,
  bool removeBranch = false,
}) => {
  'id': 'cleanup',
  'runId': 'run',
  'digest': 'reviewed-digest',
  'expiresAt': 2000000000,
  'items': [
    {
      'identity': {
        'runId': 'run',
        'taskId': 'task',
        'attempt': 1,
        'baseSha': 'a' * 40,
        'workspace': {
          'id': 'workspace',
          'name': 'Implementation Attempt',
          'path': '/workspaces/feature-delivery/implementation-attempt',
          'branch': 'alera/workflows/workspace',
        },
      },
      'removeBranch': removeBranch,
      'git': {
        'headSha': 'b' * 40,
        'dirty': dirty,
        'locked': false,
        'operationInProgress': false,
        'pathsTruncated': false,
        'changedPaths': dirty ? ['src/unfinished-change.dart'] : <String>[],
      },
    },
  ],
};

Map<String, Object?> cleanupStatusFixture(String state, {bool dirty = false}) =>
    {
      'preview': cleanupPreviewFixture(dirty: dirty),
      'state': state,
      'error': state == 'attention'
          ? 'Workspace has a live terminal. Stop it explicitly before retrying.'
          : null,
      'retiredWorkspaceIds': state == 'retired' ? ['workspace'] : <String>[],
    };
