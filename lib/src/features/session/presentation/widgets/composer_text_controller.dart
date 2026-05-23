import 'dart:io';

import 'package:flutter/material.dart';

class ComposerTextController extends TextEditingController {
  ComposerTextController({this._workspacePath});

  String? _workspacePath;

  set workspacePath(String? value) {
    if (_workspacePath != value) {
      _workspacePath = value;
      notifyListeners();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_workspacePath == null || _workspacePath!.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final String text = value.text;
    if (text.isEmpty) {
      return TextSpan(style: style, text: '');
    }

    final List<TextSpan> spans = <TextSpan>[];
    final RegExp mentionRegex = RegExp(r'@([^\s]+)');
    int currentOffset = 0;

    for (final RegExpMatch match in mentionRegex.allMatches(text)) {
      final String mentionPath = match.group(1)!;
      final String fullPath = '$_workspacePath/$mentionPath';
      bool fileExists = false;

      try {
        fileExists =
            File(fullPath).existsSync() || Directory(fullPath).existsSync();
      } catch (_) {
        // Ignore file system errors
      }

      // Add text before the mention
      if (match.start > currentOffset) {
        spans.add(TextSpan(text: text.substring(currentOffset, match.start)));
      }

      // Add the mention with styling
      if (fileExists) {
        spans.add(
          TextSpan(
            text: match.group(0),
            style:
                style?.copyWith(color: Colors.blue) ??
                const TextStyle(color: Colors.blue),
          ),
        );
      } else {
        spans.add(TextSpan(text: match.group(0)));
      }

      currentOffset = match.end;
    }

    // Add remaining text
    if (currentOffset < text.length) {
      spans.add(TextSpan(text: text.substring(currentOffset)));
    }

    return TextSpan(style: style, children: spans);
  }
}
