import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_option_specs.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';

/// One environment variable in the editor. A [sensitive] entry never holds
/// its value here: the value only travels through the write-only secret verbs.
class const AgentProviderEnvironmentDraft({
  required final String name,
  final bool sensitive = false,
  final String value = '',
  final bool secretSaved = false,
}) {
  AgentProviderEnvironmentDraft copyWith({
    String? name,
    bool? sensitive,
    String? value,
  }) => AgentProviderEnvironmentDraft(
    name: name ?? this.name,
    sensitive: sensitive ?? this.sensitive,
    value: (sensitive ?? this.sensitive) ? '' : (value ?? this.value),
    secretSaved: secretSaved,
  );

  String get signature => '$name\u0000${sensitive ? 1 : 0}\u0000$value';
}

/// A secret change waiting for Save: a replacement value, or a clear when
/// [value] is null. It lives only in memory and is dropped on Revert.
class const AgentProviderPendingSecret({
  required final String name,
  final String? value,
}) {
  bool get clears => value == null;
}

/// The editable launch definition of one provider instance, seeded from the
/// host's envelope, or from defaults when the host stores no override row.
class const AgentProviderInstanceDraft({
  required final String providerInstanceId,
  required final String provider,
  final String label = '',
  final bool enabled = true,
  final String executable = '',
  final List<String> args = const <String>[],
  final List<AgentProviderEnvironmentDraft> environment =
      const <AgentProviderEnvironmentDraft>[],
  final Map<String, Object?> options = const <String, Object?>{},
  final List<String> sensitiveOptions = const <String>[],
  final Set<String> savedSecretOptions = const <String>{},
  final List<String> customModels = const <String>[],
  final String? defaultModel,
  final bool isNew = false,
  final bool hasOverride = false,
}) {
  factory fromEnvelope(AgentChatProviderInstanceEnvelope envelope) =>
      AgentProviderInstanceDraft(
        providerInstanceId: envelope.providerInstanceId,
        provider: envelope.provider,
        label: envelope.label ?? '',
        enabled: envelope.enabled,
        executable: envelope.executable ?? '',
        args: envelope.args,
        environment: <AgentProviderEnvironmentDraft>[
          for (final entry in envelope.environment)
            AgentProviderEnvironmentDraft(
              name: entry.name,
              sensitive: entry.sensitive,
              value: entry.sensitive ? '' : entry.value ?? '',
              secretSaved: entry.secretSaved,
            ),
        ],
        options: envelope.options,
        sensitiveOptions: envelope.sensitiveOptions,
        savedSecretOptions: <String>{
          for (final option in envelope.secretOptions)
            if (option.secretSaved) _optionKey(option.name),
        },
        customModels: envelope.customModels,
        defaultModel: envelope.defaultModel,
        hasOverride: true,
      );

  /// A new instance of [provider] that has not been saved yet.
  factory create({
    required String providerInstanceId,
    required String provider,
    String label = '',
  }) => AgentProviderInstanceDraft(
    providerInstanceId: providerInstanceId,
    provider: provider,
    label: label,
    isNew: true,
  );

  /// Built-in instances share their provider's id; only added instances can
  /// be removed rather than reset.
  bool get isBuiltIn => providerInstanceId == provider;

  bool optionSecretSaved(String key) => savedSecretOptions.contains(key);

  /// Option keys declared write-only on save: the ones the host already
  /// treats as sensitive plus every secret option the provider accepts, so a
  /// secret can be set right after the first save.
  Set<String> get declaredSecretOptions => <String>{
    ...sensitiveOptions,
    for (final spec in agentProviderOptionSpecs(provider))
      if (spec.kind == AgentProviderOptionKind.secret) spec.key,
  };

  /// Whether the host already accepts a secret named [name] for this
  /// instance: a sensitive environment variable, or `option:<key>` for a
  /// declared sensitive option.
  bool acceptsSecret(String name) {
    if (!hasOverride) {
      return false;
    }
    const prefix = 'option:';
    if (name.startsWith(prefix)) {
      return sensitiveOptions.contains(name.substring(prefix.length));
    }
    return environment.any((entry) => entry.sensitive && entry.name == name);
  }

  AgentProviderInstanceDraft copyWith({
    String? label,
    bool? enabled,
    String? executable,
    List<String>? args,
    List<AgentProviderEnvironmentDraft>? environment,
    Map<String, Object?>? options,
    List<String>? sensitiveOptions,
    List<String>? customModels,
    String? defaultModel,
    bool resetDefaultModel = false,
  }) => AgentProviderInstanceDraft(
    providerInstanceId: providerInstanceId,
    provider: provider,
    label: label ?? this.label,
    enabled: enabled ?? this.enabled,
    executable: executable ?? this.executable,
    args: args ?? this.args,
    environment: environment ?? this.environment,
    options: options ?? this.options,
    sensitiveOptions: sensitiveOptions ?? this.sensitiveOptions,
    savedSecretOptions: savedSecretOptions,
    customModels: customModels ?? this.customModels,
    defaultModel: resetDefaultModel ? null : defaultModel ?? this.defaultModel,
    isNew: isNew,
    hasOverride: hasOverride,
  );

  /// Compares the persisted fields only, so saved-secret flags or the
  /// override marker never make a draft look edited.
  String get signature => <Object?>[
    label.trim(),
    enabled,
    executable.trim(),
    args.join('\u0001'),
    environment.map((entry) => entry.signature).join('\u0001'),
    _optionsSignature(options),
    (List<String>.of(sensitiveOptions)..sort()).join('\u0001'),
    customModels.join('\u0001'),
    defaultModel ?? '',
  ].join('\u0002');

  /// The upsert payload. Sensitive values never appear here: sensitive
  /// environment entries carry only their name, and sensitive option keys are
  /// declared in `sensitiveOptions` with their values left out of `options`.
  AgentChatProviderInstanceEdit toEdit() {
    final secretKeys = declaredSecretOptions;
    return AgentChatProviderInstanceEdit(
      providerInstanceId: providerInstanceId,
      provider: provider,
      label: label.trim(),
      enabled: enabled,
      executable: executable.trim(),
      args: List<String>.unmodifiableOf(args),
      environment: <AgentChatProviderEnvironmentEntry>[
        for (final entry in environment)
          if (entry.name.trim().isNotEmpty)
            AgentChatProviderEnvironmentEntry(
              name: entry.name.trim(),
              sensitive: entry.sensitive,
              value: entry.sensitive ? null : entry.value,
            ),
      ],
      options: <String, Object?>{
        for (final option in options.entries)
          if (!secretKeys.contains(option.key)) option.key: option.value,
      },
      sensitiveOptions: (secretKeys.toList()..sort()),
      customModels: List<String>.unmodifiableOf(customModels),
      defaultModel: defaultModel,
      resetDefaultModel: defaultModel == null,
    );
  }

  /// Problems that block Save, as sentences, in field order.
  List<String> validate() {
    final problems = <String>[];
    if (isNew && !agentProviderInstanceIdPattern.hasMatch(providerInstanceId)) {
      problems.add(
        'Instance ids use letters, digits, dots, dashes and underscores, and '
        'start with a letter.',
      );
    }
    final names = <String>{};
    for (final entry in environment) {
      final name = entry.name.trim();
      if (name.isEmpty) {
        problems.add('Every environment variable needs a name.');
        continue;
      }
      if (!agentProviderEnvironmentNamePattern.hasMatch(name)) {
        problems.add('$name is not a valid environment variable name.');
      }
      if (!names.add(name)) {
        problems.add('$name is listed more than once.');
      }
    }
    final models = <String>{};
    for (final model in customModels) {
      if (!models.add(model)) {
        problems.add('The custom model $model is listed more than once.');
      }
    }
    return problems;
  }
}

final RegExp agentProviderInstanceIdPattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9._-]{0,63}$',
);

final RegExp agentProviderEnvironmentNamePattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*$',
);

/// Secret target name for a sensitive environment variable.
String agentProviderEnvironmentSecretName(String name) => name;

/// Splits a command-line style argument string on whitespace, keeping quoted
/// runs together, so `--profile "Work Laptop"` becomes two arguments.
List<String> agentProviderSplitArguments(String text) {
  final args = <String>[];
  final current = StringBuffer();
  String? quote;
  var hasToken = false;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        current.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      hasToken = true;
      continue;
    }
    if (char.trim().isEmpty) {
      if (hasToken) {
        args.add(current.toString());
        current.clear();
        hasToken = false;
      }
      continue;
    }
    current.write(char);
    hasToken = true;
  }
  if (hasToken) {
    args.add(current.toString());
  }
  return args;
}

/// Joins arguments back into the editable text, quoting the ones with spaces.
String agentProviderJoinArguments(List<String> args) => args
    .map(
      (arg) => arg.isEmpty || arg.contains(RegExp(r'\s'))
          ? (arg.contains('"') ? "'$arg'" : '"$arg"')
          : arg,
    )
    .join(' ');

String _optionKey(String name) {
  const prefix = 'option:';
  return name.startsWith(prefix) ? name.substring(prefix.length) : name;
}

String _optionsSignature(Map<String, Object?> options) {
  final keys = options.keys.toList()..sort();
  return keys.map((key) => '$key=${options[key]}').join('\u0001');
}
