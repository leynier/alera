import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('xterm preserves Shift+Enter as CSI-u input', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.keyInput(TerminalKey.enter, shift: true);

    expect(output, <String>['\x1b[13;2u']);
  });

  test('xterm handles resize while scrollback and margins are active', () {
    final terminal = Terminal(maxLines: 120, reflowEnabled: false);

    terminal.resize(10, 5);
    for (var i = 0; i < 100; i++) {
      terminal.write('line $i\r\n');
    }

    terminal
      ..write('\x1b[1;3r')
      ..write('\x1b[3;1H')
      ..resize(14, 7);

    for (var i = 0; i < 10; i++) {
      terminal.write('\n');
    }
  });

  test('xterm reflows narrow wide-character prompts without RangeError', () {
    final terminal = Terminal();

    terminal
      ..resize(1, 4)
      ..write('📦x');

    terminal.resize(2, 4);
  });

  test(
    'xterm handles line feeds at the bottom of a scroll region after resize',
    () {
      final terminal = Terminal(maxLines: 10000);

      terminal
        ..resize(56, 27)
        ..resize(105, 35)
        ..write('\x1b[?2026h\x1b[1;35r\x1b[1;1H')
        ..write('\x1bM\x1bM\x1bM\x1bM\x1bM\x1bM\x1bM\x1bM\x1bM')
        ..write('\x1b[r\x1b[1;9r\x1b[1;1H\r\n');

      for (var i = 0; i < 12; i++) {
        terminal.write('\x1b[;m\x1b[K\x1b[m\x1b[m\x1b[0m\r\n');
      }
    },
  );

  test('xterm does not restore stale alt-buffer cells after resize', () {
    final terminal = Terminal(reflowEnabled: false);

    terminal
      ..resize(12, 4)
      ..write('\x1b[?1049h')
      ..write('left-stale')
      ..resize(4, 4)
      ..write('\r\x1b[Knew')
      ..resize(12, 4);

    expect(terminal.buffer.lines[0].toString(), 'new');
  });

  test(
    'xterm does not reveal stale main-buffer rows after Claude-like resize',
    () {
      final terminal = Terminal();

      terminal
        ..resize(20, 6)
        ..write('\x1b[?25l');

      for (var i = 0; i < 6; i++) {
        terminal.write('\x1b[${i + 1};1Hold row $i');
      }

      terminal.resize(20, 3);

      for (var i = 0; i < 3; i++) {
        terminal.write('\x1b[${i + 1};1H\x1b[2Knew row $i');
      }

      terminal.resize(20, 6);

      expect(terminal.buffer.lines[0].toString(), 'new row 0');
      expect(terminal.buffer.lines[1].toString(), 'new row 1');
      expect(terminal.buffer.lines[2].toString(), 'new row 2');
      expect(terminal.buffer.lines[3].toString(), isEmpty);
      expect(terminal.buffer.lines[4].toString(), isEmpty);
      expect(terminal.buffer.lines[5].toString(), isEmpty);
    },
  );

  test(
    'xterm clears hidden main-buffer cells with reflow enabled after resize',
    () {
      final terminal = Terminal();

      terminal
        ..resize(18, 4)
        ..write('\x1b[?25l')
        ..write('Claude Code ---- stale-right');

      terminal
        ..resize(10, 4)
        ..write('\x1b[1;1H\x1b[2KClaude');

      terminal.resize(18, 4);

      expect(terminal.buffer.lines[0].toString(), 'Claude');
    },
  );

  test(
    'xterm discards incremental resize scrollback for cursor-hidden apps',
    () {
      final terminal = Terminal();

      terminal
        ..resize(24, 8)
        ..write('\x1b[?25l');

      for (var i = 0; i < 8; i++) {
        terminal.write('\x1b[${i + 1};1Hold frame one $i');
      }

      terminal.resize(24, 6);
      for (var i = 0; i < 6; i++) {
        terminal.write('\x1b[${i + 1};1H\x1b[2Kold frame two $i');
      }

      terminal.resize(24, 4);
      for (var i = 0; i < 4; i++) {
        terminal.write('\x1b[${i + 1};1H\x1b[2Knew frame $i');
      }

      terminal.resize(24, 8);

      expect(terminal.buffer.lines[0].toString(), 'new frame 0');
      expect(terminal.buffer.lines[1].toString(), 'new frame 1');
      expect(terminal.buffer.lines[2].toString(), 'new frame 2');
      expect(terminal.buffer.lines[3].toString(), 'new frame 3');
      expect(terminal.buffer.lines[4].toString(), isEmpty);
      expect(terminal.buffer.lines[5].toString(), isEmpty);
      expect(terminal.buffer.lines[6].toString(), isEmpty);
      expect(terminal.buffer.lines[7].toString(), isEmpty);
    },
  );
}
