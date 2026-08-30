import 'package:alera/src/features/workbench/presentation/terminal_link_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart' as xterm;

void main() {
  test('native links follow reflow and disappear when overwritten', () {
    final terminal = xterm.Terminal()..resize(10, 4);
    addTearDown(terminal.dispose);
    terminal.write(
      '\x1b]8;;https://example.com\x1b\\abcdef'
      '\x1b]8;;\x1b\\',
    );
    terminal.resize(4, 4);
    final link = resolveTerminalLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(1, 1),
    );
    expect(link?.start, const xterm.CellOffset(0, 0));
    expect(link?.end, const xterm.CellOffset(2, 1));
    terminal.setCursor(0, 1 - terminal.buffer.scrollBack);
    terminal.write('XX');
    expect(
      resolveTerminalLinkAt(
        terminal: terminal,
        offset: const xterm.CellOffset(1, 1),
      ),
      isNull,
    );
  });

  test('visible URL spans include combining characters in their label', () {
    final terminal = xterm.Terminal()..resize(80, 4);
    addTearDown(terminal.dispose);
    terminal.write('https://example.com/e\u0301');
    final link = resolveVisibleHttpLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(20, 0),
    );
    expect(link?.uri, Uri.parse('https://example.com/e\u0301'));
    expect(link?.end.x, 21);
  });

  test('terminal link ranges handle multiline containment and equality', () {
    final range = TerminalLinkRange(
      uri: Uri.parse('https://example.com'),
      start: const xterm.CellOffset(2, 1),
      end: const xterm.CellOffset(4, 3),
    );
    final sameRange = TerminalLinkRange(
      uri: Uri.parse('https://example.com'),
      start: const xterm.CellOffset(2, 1),
      end: const xterm.CellOffset(4, 3),
    );

    expect(range.contains(const xterm.CellOffset(2, 1)), isTrue);
    expect(range.contains(const xterm.CellOffset(10, 2)), isTrue);
    expect(range.contains(const xterm.CellOffset(3, 3)), isTrue);
    expect(range.contains(const xterm.CellOffset(1, 1)), isFalse);
    expect(range.contains(const xterm.CellOffset(4, 3)), isFalse);
    expect(range.contains(const xterm.CellOffset(0, 4)), isFalse);
    expect(range, sameRange);
    expect(range.hashCode, sameRange.hashCode);
  });

  test('resolves visible http links and trims trailing punctuation', () {
    final terminal = xterm.Terminal();
    terminal.resize(80, 24);
    terminal.write('See https://example.com/docs).');

    final link = resolveVisibleHttpLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(6, 0),
    );

    expect(link, isNotNull);
    expect(link!.uri, Uri.parse('https://example.com/docs'));
    expect(link.start, const xterm.CellOffset(4, 0));
  });

  test('resolves visible http links across wrapped rows', () {
    final terminal = xterm.Terminal();
    terminal.resize(10, 24);
    terminal.write('https://example.com/path');

    final link = resolveVisibleHttpLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(2, 1),
    );

    expect(link, isNotNull);
    expect(link!.uri.toString(), 'https://example.com/path');
    expect(link.start, const xterm.CellOffset(0, 0));
    expect(link.end.y, greaterThan(0));
  });

  test('does not read beyond a short wrapped row after a resize', () {
    final terminal = xterm.Terminal();
    terminal.resize(516, 4);

    final shortLine = xterm.BufferLine(128);
    const url = 'https://example.com';
    for (var index = 0; index < url.length; index += 1) {
      shortLine.setCodePoint(index, url.codeUnitAt(index));
    }
    terminal.buffer.lines[0] = shortLine;
    terminal.buffer.lines[1].isWrapped = true;

    final link = resolveVisibleHttpLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(1, 0),
    );

    expect(link, isNotNull);
    expect(link!.uri, Uri.parse(url));
  });

  test('resolves a line-ending url after an astral glyph', () {
    final terminal = xterm.Terminal();
    terminal.resize(200, 24);
    const url = 'https://example.com';
    terminal.write('${'😀'.padRight(135)}$url');

    final link = resolveVisibleHttpLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(136, 0),
    );

    expect(link, isNotNull);
    expect(link!.uri, Uri.parse(url));
    expect(link.start, const xterm.CellOffset(135, 0));
    expect(link.end, const xterm.CellOffset(154, 0));
  });

  test('ignores offsets outside visible urls and trims ] and } suffixes', () {
    final terminal = xterm.Terminal();
    terminal.resize(80, 24);
    terminal.write('See https://example.com/path]} afterwards');

    expect(
      resolveVisibleHttpLinkAt(
        terminal: terminal,
        offset: const xterm.CellOffset(0, 4),
      ),
      isNull,
    );
    expect(
      resolveVisibleHttpLinkAt(
        terminal: terminal,
        offset: const xterm.CellOffset(0, 0),
      ),
      isNull,
    );

    final link = resolveVisibleHttpLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(8, 0),
    );

    expect(link, isNotNull);
    expect(link!.uri.toString(), 'https://example.com/path');
  });

  test('resolves native OSC 8 hyperlinks', () {
    final terminal = xterm.Terminal();
    terminal.resize(80, 24);
    addTearDown(terminal.dispose);

    terminal.write('\x1b]8;;https://example.com\x1b\\click here\x1b]8;;\x1b\\');

    final link = resolveTerminalLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(2, 0),
    );

    expect(link, isNotNull);
    expect(link!.uri, Uri.parse('https://example.com'));
  });

  test('tracks active osc8 links before they are explicitly closed', () {
    final terminal = xterm.Terminal();
    terminal.resize(80, 24);
    addTearDown(terminal.dispose);

    terminal.write('\x1b]8;;https://example.com\x1b\\');
    terminal.write('hover me');

    final link = resolveTerminalLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(2, 0),
    );

    expect(link, isNotNull);
    expect(link!.uri, Uri.parse('https://example.com'));
  });

  test('ignores invalid osc8 targets and discards empty links on close', () {
    final terminal = xterm.Terminal();
    terminal.resize(80, 24);
    addTearDown(terminal.dispose);

    terminal.write('\x1b]8;;mailto:test@example.com\x1b\\');
    expect(
      resolveTerminalLinkAt(
        terminal: terminal,
        offset: const xterm.CellOffset(0, 0),
      ),
      isNull,
    );

    terminal.write('\x1b]8;;https://example.com\x1b\\');
    terminal.write('\x1b]8;;\x1b\\');

    expect(
      resolveTerminalLinkAt(
        terminal: terminal,
        offset: const xterm.CellOffset(0, 0),
      ),
      isNull,
    );
  });

  test('keeps visible url spans aligned after wide characters', () {
    final terminal = xterm.Terminal();
    terminal.resize(80, 24);
    terminal.write('中 https://example.com');

    final link = resolveVisibleHttpLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(4, 0),
    );

    expect(link, isNotNull);
    expect(link!.uri, Uri.parse('https://example.com'));
  });

  test('treats skipped blank cells as spaces when resolving visible links', () {
    final terminal = xterm.Terminal();
    terminal.resize(80, 24);
    terminal.write('\x1b[2Chttps://example.com');

    final link = resolveVisibleHttpLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(4, 0),
    );

    expect(link, isNotNull);
    expect(link!.start, const xterm.CellOffset(2, 0));
    expect(link.uri, Uri.parse('https://example.com'));
  });

  test('discards native OSC 8 links after scrolling them away', () {
    final terminal = xterm.Terminal(maxLines: 64);
    terminal.resize(8, 4);
    addTearDown(terminal.dispose);

    terminal.write('\x1b]8;;https://example.com\x1b\\');
    terminal.write('link');
    terminal.write('\x1b]8;;\x1b\\');
    for (var index = 0; index < 100; index += 1) {
      terminal.write('\r\nline $index');
    }

    expect(
      resolveTerminalLinkAt(
        terminal: terminal,
        offset: const xterm.CellOffset(0, 0),
      ),
      isNull,
    );
  });
}
