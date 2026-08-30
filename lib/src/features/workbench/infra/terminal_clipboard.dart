import 'dart:io';

import 'package:alera/src/rust/api/clipboard.dart' as native_clipboard;
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

abstract interface class TerminalClipboard {
  Future<String?> readText();

  Future<void> writeText(String text);

  Future<List<String>> readFilePaths();

  Future<String?> saveImageAsTempFile();
}

final class const NativeTerminalClipboard() implements TerminalClipboard {
  static const MethodChannel _linuxClipboardChannel = MethodChannel(
    'dev.leynier.alera/clipboard',
  );

  @override
  Future<String?> readText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  Future<void> writeText(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Future<List<String>> readFilePaths() => Pasteboard.files();

  @override
  Future<String?> saveImageAsTempFile() {
    if (Platform.isLinux) {
      return _linuxClipboardChannel.invokeMethod<String>('saveImageAsTempFile');
    }
    return native_clipboard.saveClipboardImageAsTempFile();
  }
}
