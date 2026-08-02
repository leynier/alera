import 'package:alera/src/features/workbench/domain/worktree_navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';

WorktreeNavigationTarget _target(String id) {
  return WorktreeNavigationTarget(
    projectId: 'project-$id',
    workspaceId: 'workspace-$id',
  );
}

void main() {
  test('navigation targets use value identity and a readable string', () {
    final target = _target('a');
    final equalTarget = WorktreeNavigationTarget(
      projectId: 'project-a',
      workspaceId: 'workspace-a',
    );

    expect(target, equalTarget);
    expect(target.hashCode, equalTarget.hashCode);
    expect(
      target.toString(),
      'WorktreeNavigationTarget(project-a, workspace-a)',
    );
  });

  test('initial selection creates a current entry without back or forward', () {
    final history = WorktreeNavigationHistory();

    expect(history.record(_target('a')), isTrue);
    expect(history.canGoBack, isFalse);
    expect(history.canGoForward, isFalse);
  });

  test('consecutive duplicate selections are suppressed', () {
    final history = WorktreeNavigationHistory();
    final target = _target('a');

    expect(history.record(target), isTrue);
    expect(history.record(target), isFalse);
    expect(history.canGoBack, isFalse);
  });

  test('back and forward preserve the selected path', () {
    final history = WorktreeNavigationHistory();
    final targets = <WorktreeNavigationTarget>[
      _target('a'),
      _target('b'),
      _target('c'),
    ];
    for (final target in targets) {
      history.record(target);
    }

    expect(history.peekBack(isValid: (_) => true), targets[1]);
    history.commitBack(targets[1]);
    expect(history.peekBack(isValid: (_) => true), targets[0]);
    expect(history.peekForward(isValid: (_) => true), targets[2]);

    history.commitForward(targets[2]);
    expect(history.canGoBack, isTrue);
    expect(history.canGoForward, isFalse);
  });

  test('a new selection after going back truncates forward history', () {
    final history = WorktreeNavigationHistory();
    final first = _target('a');
    final second = _target('b');
    final third = _target('c');
    final replacement = _target('d');
    history.record(first);
    history.record(second);
    history.record(third);

    history.commitBack(second);
    history.record(replacement);

    expect(history.canGoForward, isFalse);
    expect(history.peekBack(isValid: (_) => true), second);
  });

  test('invalid targets are pruned from both directions', () {
    final history = WorktreeNavigationHistory();
    final first = _target('a');
    final second = _target('b');
    final third = _target('c');
    final fourth = _target('d');
    final live = <WorktreeNavigationTarget>{first, third, fourth};
    history.record(first);
    history.record(second);
    history.record(third);
    history.commitBack(second);
    history.record(fourth);

    history.prune(live.contains);

    expect(history.canGoBack, isTrue);
    expect(history.peekBack(isValid: live.contains), first);
    expect(history.canGoForward, isFalse);
  });

  test('back and forward at their boundaries are no-ops', () {
    final history = WorktreeNavigationHistory();
    final target = _target('a');
    history.record(target);

    expect(history.peekBack(isValid: (_) => true), isNull);
    expect(history.peekForward(isValid: (_) => true), isNull);
  });

  test('pruning an invalid current target resets the cursor', () {
    final history = WorktreeNavigationHistory();
    history.record(_target('a'));

    history.prune((_) => false);
    history.record(_target('b'));

    expect(history.canGoBack, isFalse);
  });

  test('stale back and forward commits are rejected', () {
    final history = WorktreeNavigationHistory();
    final first = _target('a');
    final second = _target('b');
    history.record(first);
    history.record(second);

    expect(() => history.commitBack(_target('missing')), throwsStateError);

    history.commitBack(first);
    expect(() => history.commitForward(_target('missing')), throwsStateError);
  });
}
