import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

enum AgentChatElicitationFieldKind { text, integer, number, boolean }

/// One field of a flat MCP form, read from its JSON schema property.
class const AgentChatElicitationField({
  required final String key,
  required final String label,
  required final AgentChatElicitationFieldKind kind,
  required final bool isRequired,
  final String? helper,
  final Object? initial,
}) {
  factory parse(String key, Object? schema, {required bool isRequired}) {
    final json = agentChatJsonMap(schema);
    return AgentChatElicitationField(
      key: key,
      label: agentChatJsonString(json['title']) ?? key,
      helper: agentChatJsonString(json['description']),
      kind: switch (json['type']) {
        'integer' => .integer,
        'number' => .number,
        'boolean' => .boolean,
        _ => .text,
      },
      isRequired: isRequired,
      initial: json['default'],
    );
  }

  String get initialText => switch (initial) {
    final String text => text,
    final num number => '$number',
    _ => '',
  };
}

/// What the user has entered in a flat MCP form, and whether it is valid.
/// Only an elicitation whose form Alera can render has fields.
class AgentChatElicitationForm {
  AgentChatElicitationForm(AgentChatElicitation? elicitation)
    : fields = <AgentChatElicitationField>[
        if (elicitation != null && elicitation.hasSupportedForm)
          for (final MapEntry(:key, :value) in elicitation.properties.entries)
            AgentChatElicitationField.parse(
              key,
              value,
              isRequired: elicitation.requiredFields.contains(key),
            ),
      ] {
    for (final field in fields) {
      if (field.kind == .boolean) {
        _flags[field.key] = field.initial == true;
        continue;
      }
      final initialText = field.initialText;
      _text[field.key] = TextEditingController(text: initialText);
      if (initialText.isNotEmpty) _checked.add(field.key);
    }
  }

  final List<AgentChatElicitationField> fields;
  final Map<String, TextEditingController> _text =
      <String, TextEditingController>{};
  final Map<String, bool> _flags = <String, bool>{};

  /// Fields whose errors are on screen: those the user edited and those the
  /// server prefilled. An untouched empty field stays quiet, while a bad
  /// default still shows why Accept is disabled.
  final Set<String> _checked = <String>{};

  TextEditingController? textOf(AgentChatElicitationField field) =>
      _text[field.key];

  bool flagOf(AgentChatElicitationField field) => _flags[field.key] ?? false;

  void setFlag(AgentChatElicitationField field, bool value) {
    _flags[field.key] = value;
  }

  void markEdited(AgentChatElicitationField field) {
    _checked.add(field.key);
  }

  String? errorOf(AgentChatElicitationField field) {
    if (field.kind == .boolean) return null;
    final text = _text[field.key]?.text.trim() ?? '';
    if (text.isEmpty) {
      return field.isRequired ? 'This field is required.' : null;
    }
    return switch (field.kind) {
      .integer when int.tryParse(text) == null => 'Enter a whole number.',
      .number when !(double.tryParse(text)?.isFinite ?? false) =>
        'Enter a number.',
      _ => null,
    };
  }

  String? visibleErrorOf(AgentChatElicitationField field) =>
      _checked.contains(field.key) ? errorOf(field) : null;

  bool get isValid => fields.every((field) => errorOf(field) == null);

  /// The typed values to send: every boolean, and the other fields that hold
  /// anything.
  Map<String, Object?> content() {
    final content = <String, Object?>{};
    for (final field in fields) {
      if (field.kind == .boolean) {
        content[field.key] = flagOf(field);
        continue;
      }
      final raw = _text[field.key]?.text ?? '';
      final text = raw.trim();
      if (text.isEmpty) continue;
      content[field.key] = switch (field.kind) {
        .integer => int.parse(text),
        .number => double.parse(text),
        _ => raw,
      };
    }
    return content;
  }

  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
  }
}

/// The fields of [form]: a text field per string, number or integer field
/// and a checkbox per boolean one, each with its description below it.
class const AgentChatElicitationFields({
  super.key,
  required final AgentChatElicitationForm form,
  required final bool enabled,
  required final VoidCallback onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space12,
      children: <Widget>[
        for (final field in form.fields) _buildField(theme, field),
      ],
    );
  }

  Widget _buildField(ThemeData theme, AgentChatElicitationField field) {
    final control = field.kind == .boolean
        ? Align(
            alignment: Alignment.centerLeft,
            child: AleraCheckbox(
              value: form.flagOf(field),
              label: field.label,
              enabled: enabled,
              onChanged: (value) {
                form.setFlag(field, value);
                onChanged();
              },
            ),
          )
        : AleraTextField(
            controller: form.textOf(field),
            labelText: field.isRequired ? '${field.label} *' : field.label,
            errorText: form.visibleErrorOf(field),
            keyboardType: switch (field.kind) {
              .integer => const TextInputType.numberWithOptions(signed: true),
              .number => const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              _ => TextInputType.text,
            },
            enabled: enabled,
            onChanged: (_) {
              form.markEdited(field);
              onChanged();
            },
          );
    final helper = field.helper;
    if (helper == null) return control;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space4,
      children: <Widget>[
        control,
        Text(
          helper,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
    );
  }
}
