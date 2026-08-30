import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xterm2/xterm.dart' as xterm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native terminal selection, shortcuts and unicode clipboard', (
    tester,
  ) async {
    // This test owns the clipboard. Only disposable CI desktops or a separate
    // Xvfb display may opt in; never run it against a user's desktop session.
    expect(Platform.environment['ALERA_NATIVE_TEST_CLIPBOARD'], '1');
    const clipboard = NativeTerminalClipboard();
    final copied = Completer<void>();
    final pasted = Completer<void>();
    final output = StringBuffer();
    final terminal = xterm.Terminal(onOutput: output.write);
    final controller = xterm.TerminalController();
    final focus = FocusNode();
    const selection = 'alera native input';
    terminal.write('$selection\r\n');

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: xterm.TerminalView(
              terminal,
              controller: controller,
              focusNode: focus,
              autofocus: true,
              cursorBlink: false,
              textStyle: xterm.TerminalStyle(
                fontFamily: AleraTokens.monoStyle.fontFamily!,
                fontSize: AleraTokens.monoStyle.fontSize!,
              ),
              shortcuts: xterm.clipboardTerminalShortcuts,
              onCopy: (text) async {
                await clipboard.writeText(text);
                copied.complete();
              },
              onPaste: () async {
                final text = await clipboard.readText();
                if (text != null) terminal.paste(text);
                pasted.complete();
              },
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(selection.length, 0),
      );
      await tester.pump();
      await _clipboardShortcut(tester, LogicalKeyboardKey.keyC, copy: true);
      await copied.future.timeout(const Duration(seconds: 5));
      expect(await clipboard.readText(), selection);

      const unicode = 'café λ 中文';
      await clipboard.writeText(unicode);
      output.clear();
      await _clipboardShortcut(tester, LogicalKeyboardKey.keyV);
      await pasted.future.timeout(const Duration(seconds: 5));
      await tester.pump();
      expect(output.toString(), unicode);
      expect(controller.selection, isNull);

      output.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(output.toString(), '\x1b[A\r');
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      focus.dispose();
      await clipboard.writeText('');
    }
  });
}

Future<void> _clipboardShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool copy = false,
}) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  final shift = copy && !Platform.isMacOS;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  try {
    await tester.sendKeyEvent(key);
  } finally {
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
  }
}
