import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart' as ghostty;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:portable_pty/portable_pty.dart' as pty;

void main() {
  test('native asset package graph is available', () {
    expect(ghostty.GhosttyTerminalController, isNotNull);
    expect(pdfrx.PdfViewerParams, isNotNull);
    expect(pty.PortablePty, isNotNull);
  });
}
