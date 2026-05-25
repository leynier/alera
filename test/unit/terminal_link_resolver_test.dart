import 'package:alera/src/features/workbench/presentation/terminal_link_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart' as xterm;

void main() {
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

  test('tracks osc8 hyperlinks from private OSC sequences', () {
    final terminal = xterm.Terminal();
    terminal.resize(80, 24);
    final tracker = Osc8TerminalLinkTracker(terminal: terminal);
    addTearDown(tracker.dispose);
    terminal.onPrivateOSC = tracker.handlePrivateOsc;

    terminal.write('\x1b]8;;https://example.com\x1b\\click here\x1b]8;;\x1b\\');

    final link = resolveTerminalLinkAt(
      terminal: terminal,
      offset: const xterm.CellOffset(2, 0),
      osc8Tracker: tracker,
    );

    expect(link, isNotNull);
    expect(link!.uri, Uri.parse('https://example.com'));
  });

  test('tracks active osc8 links before they are explicitly closed', () {
    final terminal = xterm.Terminal();
    terminal.resize(80, 24);
    final tracker = Osc8TerminalLinkTracker(terminal: terminal);
    addTearDown(tracker.dispose);

    tracker.handlePrivateOsc('8', <String>['', 'https://example.com']);
    terminal.write('hover me');

    final link = tracker.linkAt(const xterm.CellOffset(2, 0));

    expect(link, isNotNull);
    expect(link!.uri, Uri.parse('https://example.com'));
  });

  test('ignores invalid osc8 targets and discards empty links on close', () {
    final terminal = xterm.Terminal();
    terminal.resize(80, 24);
    final tracker = Osc8TerminalLinkTracker(terminal: terminal);
    addTearDown(tracker.dispose);

    tracker.handlePrivateOsc('8', <String>['', 'mailto:test@example.com']);
    expect(tracker.linkAt(const xterm.CellOffset(0, 0)), isNull);

    tracker.handlePrivateOsc('8', <String>['', 'https://example.com']);
    tracker.handlePrivateOsc('8', const <String>['', '']);

    expect(tracker.linkAt(const xterm.CellOffset(0, 0)), isNull);
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

  test('prunes detached osc8 anchors after scrolling them away', () {
    final terminal = xterm.Terminal(maxLines: 64);
    terminal.resize(8, 4);
    final tracker = Osc8TerminalLinkTracker(terminal: terminal);
    addTearDown(tracker.dispose);

    tracker.handlePrivateOsc('8', <String>['', 'https://example.com']);
    terminal.write('link');
    tracker.handlePrivateOsc('8', const <String>['', '']);
    for (var index = 0; index < 100; index += 1) {
      terminal.write('\r\nline $index');
    }

    expect(tracker.linkAt(const xterm.CellOffset(0, 0)), isNull);
  });
}
