import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/painting.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/base16/dracula.dart' as base16;
import 'package:re_highlight/styles/github-dark-dimmed.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/monokai.dart';
import 'package:re_highlight/styles/night-owl.dart';
import 'package:re_highlight/styles/nord.dart';
import 'package:re_highlight/styles/tokyo-night-dark.dart';
import 'package:re_highlight/styles/vs2015.dart';

abstract final class EditorSyntaxThemeNames {
  static const String alera = 'Alera';
  static const String githubDark = 'GitHub Dark';
  static const String githubDarkDimmed = 'GitHub Dark Dimmed';
  static const String vs2015 = 'VS2015';
  static const String atomOneDark = 'Atom One Dark';
  static const String nightOwl = 'Night Owl';
  static const String nord = 'Nord';
  static const String monokai = 'Monokai';
  static const String tokyoNightDark = 'Tokyo Night Dark';
  static const String dracula = 'Dracula';
}

class const EditorSyntaxThemeEntry({
  required final String name,
  required final Map<String, TextStyle> theme,
});

final List<EditorSyntaxThemeEntry> editorSyntaxThemeCatalog =
    List<EditorSyntaxThemeEntry>.unmodifiableOf(<EditorSyntaxThemeEntry>[
      const EditorSyntaxThemeEntry(
        name: EditorSyntaxThemeNames.alera,
        theme: _aleraEditorSyntaxTheme,
      ),
      EditorSyntaxThemeEntry(
        name: EditorSyntaxThemeNames.githubDark,
        theme: githubDarkTheme,
      ),
      EditorSyntaxThemeEntry(
        name: EditorSyntaxThemeNames.githubDarkDimmed,
        theme: githubDarkDimmedTheme,
      ),
      EditorSyntaxThemeEntry(
        name: EditorSyntaxThemeNames.vs2015,
        theme: vs2015Theme,
      ),
      EditorSyntaxThemeEntry(
        name: EditorSyntaxThemeNames.atomOneDark,
        theme: atomOneDarkTheme,
      ),
      EditorSyntaxThemeEntry(
        name: EditorSyntaxThemeNames.nightOwl,
        theme: nightOwlTheme,
      ),
      EditorSyntaxThemeEntry(
        name: EditorSyntaxThemeNames.nord,
        theme: nordTheme,
      ),
      EditorSyntaxThemeEntry(
        name: EditorSyntaxThemeNames.monokai,
        theme: monokaiTheme,
      ),
      EditorSyntaxThemeEntry(
        name: EditorSyntaxThemeNames.tokyoNightDark,
        theme: tokyoNightDarkTheme,
      ),
      EditorSyntaxThemeEntry(
        name: EditorSyntaxThemeNames.dracula,
        theme: base16.draculaTheme,
      ),
    ]);

final List<String> editorSyntaxThemeNames = List<String>.unmodifiableOf(
  editorSyntaxThemeCatalog.map((entry) => entry.name),
);

EditorSyntaxThemeEntry? editorSyntaxThemeEntryForName(String name) {
  final normalized = name.trim().toLowerCase();
  for (final entry in editorSyntaxThemeCatalog) {
    if (entry.name.toLowerCase() == normalized) {
      return entry;
    }
  }
  return null;
}

Map<String, TextStyle> editorSyntaxThemeForName(String name) {
  return editorSyntaxThemeEntryForName(name)?.theme ??
      editorSyntaxThemeCatalog.first.theme;
}

TextStyle editorSyntaxRootStyleForName(String name) {
  return editorSyntaxThemeForName(name)['root']!;
}

const Map<String, TextStyle> _aleraEditorSyntaxTheme = <String, TextStyle>{
  'root': TextStyle(
    color: AleraTokens.foreground,
    backgroundColor: AleraTokens.bg,
  ),
  'keyword': TextStyle(color: AleraTokens.syntaxKeyword),
  'meta-keyword': TextStyle(color: AleraTokens.syntaxKeyword),
  'template-tag': TextStyle(color: AleraTokens.syntaxKeyword),
  'operator': TextStyle(color: AleraTokens.syntaxOperator),
  'function': TextStyle(color: AleraTokens.syntaxFunction),
  'title': TextStyle(color: AleraTokens.syntaxFunction),
  'title.function_': TextStyle(color: AleraTokens.syntaxFunction),
  'string': TextStyle(color: AleraTokens.success),
  'meta-string': TextStyle(color: AleraTokens.success),
  'comment': TextStyle(color: AleraTokens.foregroundFaint),
  'quote': TextStyle(color: AleraTokens.foregroundFaint),
  'number': TextStyle(color: AleraTokens.warning),
  'literal': TextStyle(color: AleraTokens.syntaxLiteral),
  'built_in': TextStyle(color: AleraTokens.syntaxLiteral),
  'variable': TextStyle(color: AleraTokens.syntaxVariable),
  'type': TextStyle(color: AleraTokens.syntaxOperator),
  'title.class_': TextStyle(color: AleraTokens.syntaxLiteral),
  'class-title': TextStyle(color: AleraTokens.syntaxLiteral),
  'attr': TextStyle(color: AleraTokens.syntaxLiteral),
  'attribute': TextStyle(color: AleraTokens.syntaxLiteral),
  'meta': TextStyle(color: AleraTokens.foregroundMuted),
  'selector-tag': TextStyle(color: AleraTokens.syntaxKeyword),
  'selector-class': TextStyle(color: AleraTokens.syntaxLiteral),
  'selector-attr': TextStyle(color: AleraTokens.syntaxLiteral),
  'selector-pseudo': TextStyle(color: AleraTokens.syntaxOperator),
  'name': TextStyle(color: AleraTokens.syntaxFunction),
  'subst': TextStyle(color: AleraTokens.foreground),
  'addition': TextStyle(color: AleraTokens.success),
  'deletion': TextStyle(color: AleraTokens.error),
};
