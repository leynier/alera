import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class MobileCodexComposerDraft {
  const MobileCodexComposerDraft({
    this.value = const TextEditingValue(),
    this.attachments = const <Map<String, Object?>>[],
    this.catalogSelections = const <Map<String, Object?>>[],
  });

  final TextEditingValue value;
  final List<Map<String, Object?>> attachments;
  final List<Map<String, Object?>> catalogSelections;

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
