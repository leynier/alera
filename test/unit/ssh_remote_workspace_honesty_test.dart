import 'dart:io';

import 'package:alera/src/features/settings/presentation/settings_search_entries_resources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote host search copy names the Alera runtime', () {
    final entry = remoteHostSearchEntries.singleWhere(
      (candidate) => candidate.title == 'Remote Hosts',
    );
    expect(entry.description, contains('Alera runtime'));
    for (final candidate in remoteHostSearchEntries) {
      expect(candidate.description, isNot(contains('sidecar')));
      expect(candidate.description, isNot(contains('satellite')));
    }
    expect(entry.matches('install'), isTrue);
    expect(entry.matches('server'), isTrue);
    expect(
      remoteHostSearchEntries.any((candidate) => candidate.matches('offline')),
      isTrue,
    );
    expect(
      remoteHostSearchEntries.any((candidate) => candidate.matches('clone')),
      isTrue,
    );
  });

  test('remote host bootstrap docs keep runtime-only bootstrap and document New Workspace host picker', () {
    final docs = File('docs/remote-host-bootstrap.md').readAsStringSync();
    final lower = docs.toLowerCase();
    expect(lower, contains('installs and validates the alera runtime only'));
    expect(lower, isNot(contains('sidecar only')));
    expect(docs, contains('register --host-id'));
    expect(lower, contains('metadata only'));
    expect(docs, contains('workspace add'));
    expect(docs, contains('--host-id'));
    expect(lower, contains('new workspace'));
    expect(lower, contains('bootstrapped'));
  });
}
