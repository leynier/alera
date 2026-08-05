part of 'codex_chat_surface.dart';

String _safeMarkdown(String value) => value.replaceAll(
  RegExp(r'\[([^\]]+)\]\(streamdown:incomplete-link\)'),
  r'\$1',
);
