enum ComposerDraftItemKind { skill, mention }

class ComposerDraftItem {
  const ComposerDraftItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.path,
    this.tokenText,
  });

  final String id;
  final ComposerDraftItemKind kind;
  final String name;
  final String path;
  final String? tokenText;

  ComposerDraftItem copyWith({
    String? id,
    ComposerDraftItemKind? kind,
    String? name,
    String? path,
    String? tokenText,
    bool clearTokenText = false,
  }) {
    return ComposerDraftItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      path: path ?? this.path,
      tokenText: clearTokenText ? null : (tokenText ?? this.tokenText),
    );
  }
}
