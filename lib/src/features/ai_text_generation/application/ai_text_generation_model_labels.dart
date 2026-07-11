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
