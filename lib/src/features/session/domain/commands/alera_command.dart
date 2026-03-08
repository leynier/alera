enum AleraCommandKind { builtin, custom }

enum BuiltinCommandId {
  newChat,
  clear,
  compact,
  review,
  plan,
  model,
  permissions,
  rename,
  mention,
  skills,
  apps,
  status,
}

enum CustomCommandScope { user, repo }

class AleraCommand {
  const AleraCommand({
    required this.name,
    required this.description,
    required this.kind,
    this.builtinId,
    this.scope,
    this.content,
    this.argumentHint,
    this.supportsInlineArgs = false,
  });

  final String name;
  final String description;
  final AleraCommandKind kind;
  final BuiltinCommandId? builtinId;
  final CustomCommandScope? scope;
  final String? content;
  final String? argumentHint;
  final bool supportsInlineArgs;

  bool get isBuiltin => kind == AleraCommandKind.builtin;
  bool get isCustom => kind == AleraCommandKind.custom;
  String get normalizedName => name.trim().toLowerCase();

  AleraCommand copyWith({
    String? name,
    String? description,
    AleraCommandKind? kind,
    BuiltinCommandId? builtinId,
    CustomCommandScope? scope,
    String? content,
    bool clearContent = false,
    String? argumentHint,
    bool clearArgumentHint = false,
    bool? supportsInlineArgs,
  }) {
    return AleraCommand(
      name: name ?? this.name,
      description: description ?? this.description,
      kind: kind ?? this.kind,
      builtinId: builtinId ?? this.builtinId,
      scope: scope ?? this.scope,
      content: clearContent ? null : (content ?? this.content),
      argumentHint: clearArgumentHint
          ? null
          : (argumentHint ?? this.argumentHint),
      supportsInlineArgs: supportsInlineArgs ?? this.supportsInlineArgs,
    );
  }
}

const List<AleraCommand> _builtinCommands = <AleraCommand>[
  AleraCommand(
    name: 'new',
    description: 'Start a new chat',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.newChat,
  ),
  AleraCommand(
    name: 'clear',
    description: 'Clear the current chat and start a new one',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.clear,
  ),
  AleraCommand(
    name: 'compact',
    description: 'Compact the current thread context',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.compact,
  ),
  AleraCommand(
    name: 'review',
    description: 'Review the current changes',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.review,
    supportsInlineArgs: true,
  ),
  AleraCommand(
    name: 'plan',
    description: 'Switch to plan mode',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.plan,
    supportsInlineArgs: true,
  ),
  AleraCommand(
    name: 'model',
    description: 'Choose the active model',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.model,
  ),
  AleraCommand(
    name: 'permissions',
    description: 'Choose the approval mode',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.permissions,
  ),
  AleraCommand(
    name: 'rename',
    description: 'Rename the current thread',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.rename,
    supportsInlineArgs: true,
    argumentHint: '<name>',
  ),
  AleraCommand(
    name: 'mention',
    description: 'Mention a file from the workspace',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.mention,
  ),
  AleraCommand(
    name: 'skills',
    description: 'Insert a skill into the draft',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.skills,
  ),
  AleraCommand(
    name: 'apps',
    description: 'Insert an app mention into the draft',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.apps,
  ),
  AleraCommand(
    name: 'status',
    description: 'Show the current local session status',
    kind: AleraCommandKind.builtin,
    builtinId: BuiltinCommandId.status,
  ),
];

List<AleraCommand> builtinAleraCommands() =>
    List<AleraCommand>.unmodifiable(_builtinCommands);
