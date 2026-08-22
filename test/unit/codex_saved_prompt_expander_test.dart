import 'package:alera/src/features/codex_chat/domain/codex_saved_prompt_expander.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expands positional, named and complete saved prompt arguments', () {
    expect(
      expandCodexSavedPrompt(
        r'Review $1 for $TARGET with $ARGUMENTS and $$HOME.',
        r'"lib/my file.dart" target=tests extra',
      ),
      'Review lib/my file.dart for tests with '
      '"lib/my file.dart" target=tests extra and \$HOME.',
    );
  });

  test('removes unresolved saved prompt placeholders', () {
    expect(expandCodexSavedPrompt(r'$1 $2 $MISSING', 'one'), 'one');
  });

  test('preserves escaped whitespace and a trailing backslash', () {
    expect(
      expandCodexSavedPrompt(r'$1|$2', 'one\\ two tail\\'),
      'one two|tail\\',
    );
  });
}
