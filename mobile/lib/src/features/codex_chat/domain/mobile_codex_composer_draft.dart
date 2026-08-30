import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class const MobileCodexComposerDraft({
  final TextEditingValue value = const TextEditingValue(),
  final List<Map<String, Object?>> attachments = const <Map<String, Object?>>[],
  final List<Map<String, Object?>> catalogSelections =
      const <Map<String, Object?>>[],
}) {
  bool get isEmpty =>
      value.text.isEmpty && attachments.isEmpty && catalogSelections.isEmpty;

  MobileCodexComposerDraft copyWith({
    TextEditingValue? value,
    List<Map<String, Object?>>? attachments,
    List<Map<String, Object?>>? catalogSelections,
  }) => MobileCodexComposerDraft(
    value: value ?? this.value,
    attachments: attachments ?? this.attachments,
    catalogSelections: catalogSelections ?? this.catalogSelections,
  );
}
