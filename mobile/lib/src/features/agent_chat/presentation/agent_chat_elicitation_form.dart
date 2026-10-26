import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// A flat MCP form: text, number and yes/no fields. Richer schemas never
/// reach this widget; the card offers Decline and Cancel for those.
class const AgentChatElicitationForm({
  super.key,
  required final AgentChatElicitation elicitation,
  required final bool enabled,
  required final ValueChanged<Map<String, Object?>> onSubmit,
}) extends StatefulWidget {
  @override
  State<AgentChatElicitationForm> createState() =>
      _AgentChatElicitationFormState();
}

class _AgentChatElicitationFormState extends State<AgentChatElicitationForm> {
  final Map<String, TextEditingController> _text =
      <String, TextEditingController>{};
  final Map<String, bool> _flags = <String, bool>{};
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    for (final MapEntry(:key, :value)
        in widget.elicitation.properties.entries) {
      final field = agentChatJsonMap(value);
      final initial = field['default'];
      if (field['type'] == 'boolean') {
        _flags[key] = initial == true;
      } else {
        _text[key] = TextEditingController(text: initial?.toString() ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requiredFields = widget.elicitation.requiredFields;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space8,
        children: <Widget>[
          for (final MapEntry(:key, :value)
              in widget.elicitation.properties.entries)
            _field(key, agentChatJsonMap(value), requiredFields.contains(key)),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: widget.enabled ? _submit : null,
              child: const Text('Submit'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String key, Map<String, Object?> field, bool isRequired) {
    final label = agentChatJsonString(field['title']) ?? key;
    final description = agentChatJsonString(field['description']);
    if (field['type'] == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: description == null ? null : Text(description),
        value: _flags[key] ?? false,
        onChanged: widget.enabled
            ? (value) => setState(() => _flags[key] = value)
            : null,
      );
    }
    final numeric = field['type'] == 'number' || field['type'] == 'integer';
    return TextFormField(
      controller: _text[key],
      enabled: widget.enabled,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label, helperText: description),
      validator: (text) {
        final value = text?.trim() ?? '';
        if (value.isEmpty) return isRequired ? 'Required' : null;
        if (field['type'] == 'integer' && int.tryParse(value) == null) {
          return 'Enter a whole number';
        }
        if (field['type'] == 'number' && num.tryParse(value) == null) {
          return 'Enter a number';
        }
        return null;
      },
    );
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final properties = widget.elicitation.properties;
    final content = <String, Object?>{
      for (final MapEntry(:key, :value) in _flags.entries) key: value,
      for (final MapEntry(:key, value: controller) in _text.entries)
        if (controller.text.trim().isNotEmpty)
          key: switch (agentChatJsonMap(properties[key])['type']) {
            'integer' => int.parse(controller.text.trim()),
            'number' => num.parse(controller.text.trim()),
            _ => controller.text,
          },
    };
    widget.onSubmit(content);
  }
}
