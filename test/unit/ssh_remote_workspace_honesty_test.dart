import 'dart:io';

import 'package:alera/src/features/settings/presentation/settings_search_entries_resources.dart';
import 'package:alera/src/features/workbench/presentation/workspace_graph_indicators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote host search copy states sidecar bootstrap only', () {
    final entry = remoteHostSearchEntries.singleWhere(
      (candidate) => candidate.title == 'Remote Hosts',
    );
    expect(entry.description, contains('runtime sidecar'));
    expect(entry.description, contains('does not place workspaces'));
    expect(entry.matches('sidecar'), isTrue);
    expect(entry.matches('worktree'), isTrue);
  });

  test('host metadata tooltip does not imply a live remote worktree', () {
    expect(
      WorkspaceGraphChips.hostMetadataTooltip('audit-637-mac'),
      'Host metadata: audit-637-mac. Remote worktrees are not supported yet.',
    );
  });

  test(
    'remote host bootstrap docs state sidecar-only and metadata-only register',
    () {
      final docs = File('docs/remote-host-bootstrap.md').readAsStringSync();
      final lower = docs.toLowerCase();
      expect(lower, contains('sidecar only'));
      expect(docs, contains('register --host-id'));
      expect(lower, contains('metadata only'));
      expect(
        lower,
        contains('does not create or attach a managed git worktree'),
      );
      expect(docs, contains('workspace add'));
      expect(docs, contains('no `--host-id`'));
    },
  );
}
