import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/shared/infra/git/git_explorer_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortcut edits own an immutable snapshot of their input', () {
    const initial = KeyboardShortcutSettings.defaults;
    final chords = ['Mod+T'];
    final changed = initial.copyWithOverride(.newTerminalTab, chords);
    chords.add('Mod+N');

    expect(initial.overrides, isEmpty);
    expect(changed.overrides[KeyboardActionId.newTerminalTab], ['Mod+T']);
    expect(() => changed.overrides.clear(), throwsUnsupportedError);
    expect(
      () => changed.overrides[KeyboardActionId.newTerminalTab]!.add('Mod+X'),
      throwsUnsupportedError,
    );
    expect(changed.terminalPolicy, TerminalShortcutPolicy.appFirst);
  });

  test('git status snapshot retains its values after source mutation', () {
    final source = <String, GitExplorerStatus>{'main.dart': .modified};
    final snapshot = GitExplorerStatusSnapshot(source);
    source['main.dart'] = .added;
    source.clear();

    expect(snapshot.statusFor('main.dart'), GitExplorerStatus.modified);
    expect(snapshot.statusFor('missing.dart'), isNull);
    expect(() => snapshot.statuses.clear(), throwsUnsupportedError);
    expect(const GitExplorerStatusSnapshot.empty().statuses, isEmpty);
  });
}
