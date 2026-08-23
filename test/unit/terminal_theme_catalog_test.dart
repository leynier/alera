import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'terminal theme helpers resolve names, fallbacks, and legacy presets',
    () {
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
    },
  );

  test('terminal theme catalog preserves every ordered color value', () {
    expect(terminalThemeCatalog.map(_themeSnapshot).toList(), <String>[
      'Alera Dark|ff101010 fff5f5f5 ffe0e0e0 1ae0e0e0 ff606060 fff87171 ff22c55e fff59e0b ff60a5fa ffe0e0e0 ff60a5fa fff5f5f5 ffa1a1a1 fff87171 ff22c55e fff59e0b ff60a5fa ffe0e0e0 ff60a5fa fff5f5f5 ff242424 1ae0e0e0 fff5f5f5',
      'Ghostty Default Style Dark|ff282c34 ffffffff ffffffff ff3e4451 ff1d1f21 ffcc6666 ffb5bd68 fff0c674 ff81a2be ffb294bb ff8abeb7 ffc5c8c6 ff666666 ffd54e53 ffb9ca4a ffe7c547 ff7aa6da ffc397d8 ff70c0b1 ffeaeaea ff3e4451 ff666666 ffffffff',
      'Builtin Tango Light|ffffffff ff2e3434 ff2e3434 ffaccef7 ff2e3436 ffcc0000 ff4e9a06 ffc4a000 ff3465a4 ff75507b ff06989a ffd3d7cf ff555753 ffef2929 ff8ae234 fffce94f ff729fcf ffad7fa8 ff34e2e2 ffeeeeec ffaccef7 ff555753 ff2e3434',
      'Dracula|ff282a36 fff8f8f2 fff8f8f2 ff44475a ff21222c ffff5555 ff50fa7b fff1fa8c ffbd93f9 ffff79c6 ff8be9fd fff8f8f2 ff6272a4 ffff6e6e ff69ff94 ffffffa5 ffd6acff ffff92df ffa4ffff ffffffff ff44475a ff6272a4 fff8f8f2',
      'One Dark|ff282c34 ffabb2bf ff528bff ff3e4451 ff282c34 ffe06c75 ff98c379 ffe5c07b ff61afef ffc678dd ff56b6c2 ffabb2bf ff5c6370 ffe06c75 ff98c379 ffe5c07b ff61afef ffc678dd ff56b6c2 ffffffff ff3e4451 ff5c6370 ffabb2bf',
      'Nord|ff2e3440 ffd8dee9 ffd8dee9 ff434c5e ff3b4252 ffbf616a ffa3be8c ffebcb8b ff81a1c1 ffb48ead ff88c0d0 ffe5e9f0 ff4c566a ffbf616a ffa3be8c ffebcb8b ff81a1c1 ffb48ead ff8fbcbb ffeceff4 ff434c5e ff4c566a ffd8dee9',
      'Monokai|ff272822 fff8f8f2 fff8f8f0 ff49483e ff272822 fff92672 ffa6e22e fff4bf75 ff66d9ef ffae81ff ffa1efe4 fff8f8f2 ff75715e fff92672 ffa6e22e fff4bf75 ff66d9ef ffae81ff ffa1efe4 fff9f8f5 ff49483e ff75715e fff8f8f2',
      'Tokyo Night|ff1a1b26 ffc0caf5 ffc0caf5 ff33467c ff15161e fff7768e ff9ece6a ffe0af68 ff7aa2f7 ffbb9af7 ff7dcfff ffa9b1d6 ff414868 fff7768e ff9ece6a ffe0af68 ff7aa2f7 ffbb9af7 ff7dcfff ffc0caf5 ff33467c ff414868 ffc0caf5',
      'Gruvbox Dark|ff282828 ffebdbb2 ffebdbb2 ff504945 ff282828 ffcc241d ff98971a ffd79921 ff458588 ffb16286 ff689d6a ffa89984 ff928374 fffb4934 ffb8bb26 fffabd2f ff83a598 ffd3869b ff8ec07c ffebdbb2 ff504945 ff928374 ffebdbb2',
      'Catppuccin Mocha|ff1e1e2e ffcdd6f4 fff5e0dc ff585b70 ff45475a fff38ba8 ffa6e3a1 fff9e2af ff89b4fa fff5c2e7 ff94e2d5 ffbac2de ff585b70 fff38ba8 ffa6e3a1 fff9e2af ff89b4fa fff5c2e7 ff94e2d5 ffa6adc8 ff585b70 ff585b70 ffcdd6f4',
      'Solarized Dark|ff002b36 ff839496 ff839496 ff073642 ff073642 ffdc322f ff859900 ffb58900 ff268bd2 ffd33682 ff2aa198 ffeee8d5 ff002b36 ffcb4b16 ff586e75 ff657b83 ff839496 ff6c71c4 ff93a1a1 fffdf6e3 ff073642 ff002b36 ff839496',
      'Material Dark|ff263238 ffeeffff ffffcc00 ff546e7a ff000000 fff07178 ffc3e88d ffffcb6b ff82aaff ffc792ea ff89ddff ffeeffff ff546e7a fff07178 ffc3e88d ffffcb6b ff82aaff ffc792ea ff89ddff ffffffff ff546e7a ff546e7a ffeeffff',
      'Ayu Dark|ff0a0e14 ffb3b1ad ffe6b450 ff273747 ff01060e ffea6c73 ff91b362 fff9af4f ff53bdfa fffae994 ff90e1c6 ffc7c7c7 ff686868 fff07178 ffc2d94c ffffb454 ff59c2ff ffffee99 ff95e6cb ffffffff ff273747 ff686868 ffb3b1ad',
      'Nightfox|ff192330 ffcdcecf ffcdcecf ff2b3b51 ff393b44 ffc94f6d ff81b29a ffdbc074 ff719cd6 ff9d79d6 ff63cdcf ffdfdfe0 ff575860 ffd16983 ff8ebaa4 ffe0c989 ff86abdc ffbaa1e2 ff7ad5d6 ffe4e4e5 ff2b3b51 ff575860 ffcdcecf',
      'Kanagawa|ff1f1f28 ffdcd7ba ffc8c093 ff2d4f67 ff090618 ffc34043 ff76946a ffc0a36e ff7e9cd8 ff957fb8 ff6a9589 ffc8c093 ff727169 ffe82424 ff98bb6c ffe6c384 ff7fb4ca ff938aa9 ff7aa89f ffdcd7ba ff2d4f67 ff727169 ffdcd7ba',
      'Rose Pine|ff191724 ffe0def4 ff524f67 ff403d52 ff26233a ffeb6f92 ff31748f fff6c177 ff9ccfd8 ffc4a7e7 ffebbcba ffe0def4 ff6e6a86 ffeb6f92 ff31748f fff6c177 ff9ccfd8 ffc4a7e7 ffebbcba ffe0def4 ff403d52 ff6e6a86 ffe0def4',
      'Everforest Dark|ff2d353b ffd3c6aa ffd3c6aa ff543a48 ff475258 ffe67e80 ffa7c080 ffdbbc7f ff7fbbb3 ffd699b6 ff83c092 ffd3c6aa ff697379 ffe67e80 ffa7c080 ffdbbc7f ff7fbbb3 ffd699b6 ff83c092 ffd3c6aa ff543a48 ff697379 ffd3c6aa',
      'Palenight|ff292d3e ffa6accd ffffcc00 ff434758 ff292d3e fff07178 ffc3e88d ffffcb6b ff82aaff ffc792ea ff89ddff ffa6accd ff676e95 fff07178 ffc3e88d ffffcb6b ff82aaff ffc792ea ff89ddff ffffffff ff434758 ff676e95 ffa6accd',
      'Horizon Dark|ff1c1e26 ffe0e0e0 ffe95678 ff2e303e ff16161c ffe95678 ff29d398 fffab795 ff26bbd9 ffee64ac ff59e1e3 ffd5d8da ff6c6f93 ffec6a88 ff3fdaa4 fffbc3a7 ff3fc4de fff075b5 ff6be4e6 fff0f0f0 ff2e303e ff6c6f93 ffe0e0e0',
      'Night Owl|ff011627 ffd6deeb ff80a4c2 ff1d3b53 ff011627 ffef5350 ff22da6e ffaddb67 ff82aaff ffc792ea ff21c7a8 ffffffff ff575656 ffef5350 ff22da6e ffffeb95 ff82aaff ffc792ea ff7fdbca ffffffff ff1d3b53 ff575656 ffd6deeb',
      'Solarized Light|fffdf6e3 ff657b83 ff657b83 ffeee8d5 ff073642 ffdc322f ff859900 ffb58900 ff268bd2 ffd33682 ff2aa198 ffeee8d5 ff002b36 ffcb4b16 ff586e75 ff657b83 ff839496 ff6c71c4 ff93a1a1 fffdf6e3 ffeee8d5 ff002b36 ff657b83',
      'One Light|fffafafa ff383a42 ff526fff ffe5e5e6 ff383a42 ffe45649 ff50a14f ffc18401 ff4078f2 ffa626a4 ff0184bc ffa0a1a7 ff696c77 ffe45649 ff50a14f ffc18401 ff4078f2 ffa626a4 ff0184bc fffafafa ffe5e5e6 ff696c77 ff383a42',
      'Catppuccin Latte|ffeff1f5 ff4c4f69 ffdc8a78 ffacb0be ff5c5f77 ffd20f39 ff40a02b ffdf8e1d ff1e66f5 ffea76cb ff179299 ffacb0be ff6c6f85 ffd20f39 ff40a02b ffdf8e1d ff1e66f5 ffea76cb ff179299 ffbcc0cc ffacb0be ff6c6f85 ff4c4f69',
      'GitHub Light|ffffffff ff24292e ff044289 ffc8c8fa ff24292e ffd73a49 ff28a745 ffdbab09 ff0366d6 ff5a32a3 ff0598bc ff6a737d ff959da5 ffcb2431 ff22863a ffb08800 ff005cc5 ff5a32a3 ff3192aa ffd1d5da ffc8c8fa ff959da5 ff24292e',
      'Rose Pine Dawn|fffaf4ed ff575279 ff9893a5 ffdfdad9 fff2e9e1 ffb4637a ff286983 ffea9d34 ff56949f ff907aa9 ffd7827e ff575279 ff9893a5 ffb4637a ff286983 ffea9d34 ff56949f ff907aa9 ffd7827e ff575279 ffdfdad9 ff9893a5 ff575279',
      'Gruvbox Light|fffbf1c7 ff3c3836 ff3c3836 ffebdbb2 fffbf1c7 ffcc241d ff98971a ffd79921 ff458588 ffb16286 ff689d6a ff7c6f64 ff928374 ff9d0006 ff79740e ffb57614 ff076678 ff8f3f71 ff427b58 ff3c3836 ffebdbb2 ff928374 ff3c3836',
      'Tokyo Night Light|ffd5d6db ff343b58 ff343b58 ff9699a3 ff0f0f14 ff8c4351 ff485e30 ff8f5e15 ff34548a ff5a4a78 ff0f4b6e ff343b58 ff9699a3 ff8c4351 ff485e30 ff8f5e15 ff34548a ff5a4a78 ff0f4b6e ff343b58 ff9699a3 ff9699a3 ff343b58',
      'Everforest Light|fffdf6e3 ff5c6a72 ff5c6a72 ffe6e2cc ff5c6a72 fff85552 ff8da101 ffdfa000 ff3a94c5 ffdf69ba ff35a77c ffdfd9a8 ff939f91 fff85552 ff8da101 ffdfa000 ff3a94c5 ffdf69ba ff35a77c fffdf6e3 ffe6e2cc ff939f91 ff5c6a72',
      'Tango Dark|ff000000 ffd3d7cf ffd3d7cf ff555753 ff2e3436 ffcc0000 ff4e9a06 ffc4a000 ff3465a4 ff75507b ff06989a ffd3d7cf ff555753 ffef2929 ff8ae234 fffce94f ff729fcf ffad7fa8 ff34e2e2 ffeeeeec ff555753 ff555753 ffd3d7cf',
      'Homebrew|ff000000 ff00ff00 ff00ff00 ff005500 ff000000 ff990000 ff00a600 ff999900 ff0000b2 ffb200b2 ff00a6b2 ffbfbfbf ff666666 ffe50000 ff00d900 ffe5e500 ff0000ff ffe500e5 ff00e5e5 ffe5e5e5 ff005500 ff666666 ff00ff00',
      'Snazzy|ff282a36 ffeff0eb ff97979b ff3e404a ff282a36 ffff5c57 ff5af78e fff3f99d ff57c7ff ffff6ac1 ff9aedfe fff1f1f0 ff686868 ffff5c57 ff5af78e fff3f99d ff57c7ff ffff6ac1 ff9aedfe fff1f1f0 ff3e404a ff686868 ffeff0eb',
    ]);
  });
}

String _themeSnapshot(TerminalThemeEntry entry) {
  final theme = entry.theme;
  final values = <int>[
    theme.background.toARGB32(),
    theme.foreground.toARGB32(),
    theme.cursor.toARGB32(),
    theme.selection.toARGB32(),
    theme.black.toARGB32(),
    theme.red.toARGB32(),
    theme.green.toARGB32(),
    theme.yellow.toARGB32(),
    theme.blue.toARGB32(),
    theme.magenta.toARGB32(),
    theme.cyan.toARGB32(),
    theme.white.toARGB32(),
    theme.brightBlack.toARGB32(),
    theme.brightRed.toARGB32(),
    theme.brightGreen.toARGB32(),
    theme.brightYellow.toARGB32(),
    theme.brightBlue.toARGB32(),
    theme.brightMagenta.toARGB32(),
    theme.brightCyan.toARGB32(),
    theme.brightWhite.toARGB32(),
    theme.searchHitBackground.toARGB32(),
    theme.searchHitBackgroundCurrent.toARGB32(),
    theme.searchHitForeground.toARGB32(),
  ];
  final colors = values
      .map((value) => value.toRadixString(16).padLeft(8, '0'))
      .join(' ');
  return '${entry.name}|$colors';
}
