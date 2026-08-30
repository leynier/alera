import 'dart:io';
import 'dart:ui' as ui;

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:xterm2/xterm.dart' as xterm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native typography and terminal render at three scales', (
    tester,
  ) async {
    final outputPath = Platform.environment['ALERA_VISUAL_REVIEW_DIR'];
    final terminal = xterm.Terminal(maxLines: 100);
    addTearDown(terminal.dispose);
    terminal.write('JetBrains Mono: 0O 1lI {} [] => !=\r\n');
    terminal.write('Español: áéíóú ñ | Unicode: 日本語 λ ✓\r\n');
    terminal.write(
      '\x1b[31mError\x1b[0m  \x1b[32mSuccess\x1b[0m  '
      '\x1b[34mInfo\x1b[0m\r\n',
    );
    terminal.write('┌────────────┐\r\n│   Alera    │\r\n└────────────┘\r\n');

    for (final scale in [1.0, 1.5, 2.0]) {
      final key = GlobalKey();
      final theme = buildAleraDarkTheme();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(AleraTokens.space24),
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      'Alera Native Typography - Inter at ${scale}x',
                      textScaler: .linear(scale),
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      'Aa Bb 0123456789 áéíóú ñ - Light and bold',
                      textScaler: .linear(scale),
                    ),
                    Text(
                      'Monospace 0O 1lI {} [] => !=',
                      textScaler: .linear(scale),
                      style: AleraTokens.monoStyle,
                    ),
                    const SizedBox(height: AleraTokens.space16),
                    Wrap(
                      spacing: AleraTokens.space12,
                      children: [
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Primary Action'),
                        ),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Secondary Action'),
                        ),
                        const Chip(label: Text('Status')),
                      ],
                    ),
                    const SizedBox(height: AleraTokens.space16),
                    Expanded(
                      child: xterm.TerminalView(
                        terminal,
                        cursorBlink: false,
                        textStyle: xterm.TerminalStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: AleraTokens.monoStyle.fontSize! * scale,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Unlike text-obscured widget goldens, these captures use the native
      // engine and real font assets, so renderer changes can be reviewed.
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final capture = await boundary.toImage(
        pixelRatio: tester.view.devicePixelRatio,
      );
      try {
        expect(capture.width, greaterThan(0));
        expect(capture.height, greaterThan(0));
        if (outputPath != null) {
          final directory = await Directory(outputPath).create(recursive: true);
          final data = await capture.toByteData(format: ui.ImageByteFormat.png);
          await File(
            p.join(directory.path, '${Platform.operatingSystem}-${scale}x.png'),
          ).writeAsBytes(data!.buffer.asUint8List());
        }
      } finally {
        capture.dispose();
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
