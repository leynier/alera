import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editor syntax theme catalog resolves names and fallback', () {
    expect(editorSyntaxThemeNames, contains(EditorSyntaxThemeNames.alera));
    expect(editorSyntaxThemeNames, contains(EditorSyntaxThemeNames.monokai));
    expect(editorSyntaxThemeCatalog.length, 10);

    final monokai = editorSyntaxThemeEntryForName('  monokai  ');
    expect(monokai, isNotNull);
    expect(monokai!.name, EditorSyntaxThemeNames.monokai);
    expect(monokai.theme['root'], isNotNull);

    expect(
      editorSyntaxThemeForName('missing-theme'),
      same(editorSyntaxThemeCatalog.first.theme),
    );
  });

  test('alera editor syntax theme uses app design tokens', () {
    final root = editorSyntaxRootStyleForName(EditorSyntaxThemeNames.alera);

    expect(root.color, AleraTokens.foreground);
    expect(root.backgroundColor, AleraTokens.bg);
    expect(
      editorSyntaxThemeForName(EditorSyntaxThemeNames.alera)['keyword']?.color,
      AleraTokens.syntaxKeyword,
    );
  });

  test('every catalog theme defines a root style', () {
    expect(
      editorSyntaxThemeCatalog.every((entry) => entry.theme['root'] != null),
      isTrue,
    );
  });
}
