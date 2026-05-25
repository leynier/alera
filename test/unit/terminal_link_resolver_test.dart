import 'package:alera/src/features/workbench/presentation/terminal_link_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart' as xterm;

void main() {
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
}
