import 'dart:async';

import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/linked_issues/application/linked_issue_metadata_refresher.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 12, 12);

LinkedIssue _issue(
  String workspaceId, {
  DateTime? fetchedAt,
  bool fetchable = true,
  DateTime? linkedAt,
}) => LinkedIssue(
  workspaceId: workspaceId,
  url: 'https://github.com/o/r/issues/1',
  provider: fetchable ? .github : null,
  number: fetchable ? 1 : null,
  fetchedAt: fetchedAt,
  linkedAt: linkedAt ?? _now.subtract(const Duration(hours: 2)),
);

void main() {
  test('refreshes only stale fetchable links, one at a time', () async {
    final foreground = _FakeForeground();
    final refreshed = <String>[];
    var inFlight = 0;
    var maxInFlight = 0;
    final refresher = LinkedIssueMetadataRefresher(
      list: () async => <String, LinkedIssue>{
        'stale': _issue(
          'stale',
          fetchedAt: _now.subtract(const Duration(hours: 1)),
        ),
        'fresh': _issue(
          'fresh',
          fetchedAt: _now.subtract(const Duration(minutes: 5)),
        ),
        'never': _issue('never'),
        'recent': _issue('recent', linkedAt: _now),
        'url-only': _issue('url-only', fetchable: false),
      },
      refresh: (workspaceId) async {
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        await Future<void>.delayed(Duration.zero);
        refreshed.add(workspaceId);
        inFlight--;
        if (workspaceId == 'never') {
          throw StateError('gh is signed out');
        }
      },
      foreground: foreground,
      now: () => _now,
    );
    expect(refresher.isRunning, isTrue);
    await Future.wait(<Future<void>>[refresher.runPass(), refresher.runPass()]);
    await Future<void>.delayed(Duration.zero);
    expect(refreshed.toSet(), <String>{'stale', 'never'});
    expect(maxInFlight, 1);
    refresher.dispose();
    await foreground.close();
  });

  test('parks while hidden and resumes when visible', () async {
    final foreground = _FakeForeground(isForeground: false);
    var passes = 0;
    final refresher = LinkedIssueMetadataRefresher(
      list: () async {
        passes++;
        return <String, LinkedIssue>{'w': _issue('w')};
      },
      refresh: (_) async {},
      foreground: foreground,
      now: () => _now,
    );
    expect(refresher.isRunning, isFalse);
    foreground.set(true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(refresher.isRunning, isTrue);
    expect(passes, 1);
    foreground.set(false);
    await Future<void>.delayed(Duration.zero);
    expect(refresher.isRunning, isFalse);
    await refresher.runPass();
    refresher.dispose();
    foreground.set(true);
    await Future<void>.delayed(Duration.zero);
    expect(refresher.isRunning, isFalse);
    await refresher.runPass();
    await foreground.close();
  });

  test('a failing list is ignored until the next pass', () async {
    final foreground = _FakeForeground();
    final refresher = LinkedIssueMetadataRefresher(
      list: () async => throw StateError('host offline'),
      refresh: (_) async => fail('nothing to refresh'),
      foreground: foreground,
    );
    await refresher.runPass();
    refresher.dispose();
    await foreground.close();
  });
}

class _FakeForeground implements AppForeground {
  _FakeForeground({this.isForeground = true});

  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  bool isForeground;

  void set(bool value) {
    isForeground = value;
    _changes.add(value);
  }

  Future<void> close() => _changes.close();

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  void dispose() {}
}
