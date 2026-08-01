part of 'ai_text_generation_registry.dart';

String labelFromModelId(String id) {
  return id
      .split(RegExp(r'[/-]'))
      .where((part) => part.isNotEmpty)
      .map((part) {
        if (part.toLowerCase() == 'gpt') {
          return 'GPT';
        }
        if (part.length <= 3 && RegExp(r'^\d').hasMatch(part)) {
          return part.toUpperCase();
        }
        return '${part[0].toUpperCase()}${part.substring(1)}';
      })
      .join(' ');
}

String labelFromAgyModelId(String id) {
  final effort = RegExp(
    r'-(low|medium|high)$',
    caseSensitive: false,
  ).firstMatch(id);
  final thinking = RegExp(r'-thinking$', caseSensitive: false).firstMatch(id);
  final suffix = effort ?? thinking;
  final baseId = suffix == null ? id : id.substring(0, suffix.start);
  var label = labelFromModelId(baseId).replaceAllMapped(
    RegExp(r'\b(\d+) (\d+)\b'),
    (match) => '${match.group(1)}.${match.group(2)}',
  );
  if (label.contains(' Oss ')) {
    label = label.replaceFirst(' Oss ', ' OSS ');
  }
  if (effort != null) {
    final level = effort.group(1)!;
    return '$label (${level[0].toUpperCase()}${level.substring(1).toLowerCase()})';
  }
  if (thinking != null) {
    return '$label (Thinking)';
  }
  return label;
}
