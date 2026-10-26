import 'dart:async';

import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_file_search.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeSession implements AgentChatComposerFileSearchSession {
  final Map<String, Completer<List<String>>> pending =
      <String, Completer<List<String>>>{};
  final List<String> queries = <String>[];
  int closes = 0;

  @override
  Future<List<String>> search(String query, {required int limit}) {
    queries.add(query);
    return (pending[query] = Completer<List<String>>()).future;
  }

  @override
  Future<void> close() async => closes++;
}

final class _FakeSearch implements AgentChatComposerFileSearch {
  _FakeSearch([this.key = 'ws-1']);

  @override
  final String key;
  final List<_FakeSession> sessions = <_FakeSession>[];
  Object? openError;

  @override
  Future<AgentChatComposerFileSearchSession> open() async {
    if (openError case final Object error) throw error;
    final session = _FakeSession();
    sessions.add(session);
    return session;
  }

  @override
  String attachmentPath(String relativePath) => '/repo/$relativePath';
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a query waits for the debounce and searches once', () async {
    final source = _FakeSearch();
    final search = AgentChatComposerMentionSearch(
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(search.dispose);

    search
      ..search(source, 's')
      ..search(source, 'sr')
      ..search(source, 'src');
    expect(search.loading, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final session = source.sessions.single;
    expect(session.queries, <String>['src']);
    session.pending['src']!.complete(<String>['src/main.dart']);
    await _settle();
    expect(search.results, <String>['src/main.dart']);
    expect(search.loading, isFalse);
  });

  test('a result that arrives after a newer query is dropped', () async {
    final source = _FakeSearch();
    final search = AgentChatComposerMentionSearch(debounce: Duration.zero);
    addTearDown(search.dispose);

    search.search(source, 'a');
    await _settle();
    await _settle();
    search.search(source, 'ab');
    await _settle();
    await _settle();
    final session = source.sessions.single;
    session.pending['ab']!.complete(<String>['ab.dart']);
    await _settle();
    session.pending['a']!.complete(<String>['a.dart']);
    await _settle();

    expect(search.results, <String>['ab.dart']);
  });

  test('reset drops a pending result and closes the session', () async {
    final source = _FakeSearch();
    final search = AgentChatComposerMentionSearch(debounce: Duration.zero);
    addTearDown(search.dispose);

    search.search(source, 'a');
    await _settle();
    await _settle();
    final session = source.sessions.single;
    search.reset();
    session.pending['a']!.complete(<String>['a.dart']);
    await _settle();

    expect(search.results, isEmpty);
    expect(session.closes, 1);
  });

  test('another file tree closes the old session', () async {
    final first = _FakeSearch('ws-1');
    final second = _FakeSearch('ws-2');
    final search = AgentChatComposerMentionSearch(debounce: Duration.zero);
    addTearDown(search.dispose);

    search.search(first, 'a');
    await _settle();
    await _settle();
    search.search(second, 'a');
    await _settle();
    await _settle();

    expect(first.sessions.single.closes, 1);
    expect(second.sessions.single.queries, <String>['a']);
  });

  test('a failed search keeps the error and no results', () async {
    final source = _FakeSearch()..openError = StateError('index failed');
    final search = AgentChatComposerMentionSearch(debounce: Duration.zero);
    addTearDown(search.dispose);

    search.search(source, 'a');
    await _settle();
    await _settle();

    expect(search.error, isA<StateError>());
    expect(search.results, isEmpty);
    expect(search.loading, isFalse);
  });
}
