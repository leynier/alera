import 'package:alera/src/features/session/domain/commands/alera_command.dart';
import 'package:alera/src/features/session/domain/commands/command_parser.dart';
import 'package:alera/src/features/session/domain/commands/custom_command_expander.dart';
import 'package:alera/src/features/session/domain/commands/custom_command_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSlashCommand', () {
    test('parses only the first line and keeps the remaining body', () {
      final parsed = parseSlashCommand(
        '/review scope=ui "fix navbar"\nFollow up details',
      );

      expect(parsed, isNotNull);
      expect(parsed?.name, 'review');
      expect(parsed?.rawArgs, 'scope=ui "fix navbar"');
      expect(parsed?.hasArgs, isTrue);
      expect(parsed?.remainingText, 'Follow up details');
    });

    test('does not parse slash commands outside the first line', () {
      final parsed = parseSlashCommand('Normal prompt\n/review later');
      expect(parsed, isNull);
    });
  });

  group('slash query helpers', () {
    test('treats slash at column zero as an active query', () {
      expect(looksLikeSlashQuery('/', 1), isTrue);
      expect(extractSlashQuery('/', 1), '');
    });

    test(
      'stops treating input as a slash query after command arguments begin',
      () {
        expect(looksLikeSlashQuery('/review main', 12), isFalse);
        expect(extractSlashQuery('/review main', 12), '');
      },
    );
  });

  group('parseCustomCommandFrontmatter', () {
    test('reads description and argument hint from frontmatter', () {
      final parsed = parseCustomCommandFrontmatter('''
---
description: "Review the current diff"
argument-hint: "<path> [--staged]"
ignored: true
---
# Review
Use \$ARGUMENTS and \$\$ safely.
''');

      expect(parsed.description, 'Review the current diff');
      expect(parsed.argumentHint, '<path> [--staged]');
      expect(parsed.body, '# Review\nUse \$ARGUMENTS and \$\$ safely.\n');
    });
  });

  group('expandCustomCommand', () {
    test('expands positional, named, raw and escaped placeholders', () {
      final command = const AleraCommand(
        name: 'review-diff',
        description: 'Review a diff',
        kind: AleraCommandKind.custom,
        scope: CustomCommandScope.repo,
        content:
            'Raw:\$ARGUMENTS\nFirst:\$1\nSecond:\$2\nScope:\$SCOPE\nLiteral:\$\$',
      );

      final expanded = expandCustomCommand(
        command,
        'scope=frontend src/app.dart "extra notes"',
      );

      expect(
        expanded.text,
        'Raw:scope=frontend src/app.dart "extra notes"\n'
        'First:src/app.dart\n'
        'Second:extra notes\n'
        'Scope:frontend\n'
        'Literal:\$',
      );
      expect(expanded.positionalArgs, <String>['src/app.dart', 'extra notes']);
      expect(expanded.namedArgs, <String, String>{'SCOPE': 'frontend'});
    });
  });
}
