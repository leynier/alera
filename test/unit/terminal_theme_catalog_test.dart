import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('terminal theme helpers resolve names, fallbacks, and legacy presets', () {
    expect(terminalThemeNames, contains(TerminalThemeNames.aleraDark));
    expect(terminalThemeNames, contains(TerminalThemeNames.dracula));

    final dracula = terminalThemeEntryForName('  dracula  ');
    expect(dracula, isNotNull);
    expect(dracula!.name, TerminalThemeNames.dracula);

    expect(
      terminalThemeForName('missing-theme'),
      same(terminalThemeCatalog.first.theme),
    );
    expect(
      terminalThemeNameFromLegacyPreset('ghosttyDark'),
      TerminalThemeNames.ghosttyDark,
    );
    expect(terminalThemeNameFromLegacyPreset('unknown'), isNull);
  });
}
