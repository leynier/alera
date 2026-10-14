import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_instance_draft.dart';
import 'package:flutter/material.dart';

/// A dense text field bound to a draft value. It owns its controller and
/// takes a new [value] from outside (Revert, a reload) only while it is not
/// being edited, so a rebuild never moves the caret.
class const AgentProviderTextField({
  super.key,
  required final String value,
  required final ValueChanged<String> onChanged,
  final String? hintText,
  final bool enabled = true,
  final String? errorText,
}) extends StatefulWidget {
  @override
  State<AgentProviderTextField> createState() => _AgentProviderTextFieldState();
}

class _AgentProviderTextFieldState extends State<AgentProviderTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(AgentProviderTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AleraTextField(
      controller: _controller,
      focusNode: _focusNode,
      hintText: widget.hintText,
      errorText: widget.errorText,
      enabled: widget.enabled,
      dense: true,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onChanged,
    );
  }
}

/// A write-only secret. It shows whether a value is saved on the host and
/// what Save will do, but never a saved value: Replace and Set take a new
/// value in an obscured field that is cleared once it is handed over.
class const AgentProviderSecretControl({
  super.key,
  required final String name,
  required final bool saved,
  required final AgentProviderPendingSecret? pending,
  required final ValueChanged<String> onSet,
  required final VoidCallback onClear,
  required final VoidCallback onUndo,
  final bool enabled = true,
}) extends StatefulWidget {
  @override
  State<AgentProviderSecretControl> createState() =>
      _AgentProviderSecretControlState();
}

class _AgentProviderSecretControlState
    extends State<AgentProviderSecretControl> {
  final TextEditingController _controller = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final value = _controller.text;
    if (value.isEmpty) {
      return;
    }
    widget.onSet(value);
    _controller.clear();
    setState(() => _editing = false);
  }

  void _cancel() {
    _controller.clear();
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Row(
        children: <Widget>[
          Expanded(
            child: AleraTextField(
              controller: _controller,
              hintText: 'New value for ${widget.name}',
              obscureText: true,
              autofocus: true,
              dense: true,
              autocorrect: false,
              enableSuggestions: false,
              textActionsEnabled: false,
              onSubmitted: (_) => _commit(),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          TextButton(onPressed: _cancel, child: const Text('Cancel')),
          const SizedBox(width: AleraTokens.space4),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => FilledButton(
              onPressed: _controller.text.isEmpty ? null : _commit,
              child: const Text('Use Value'),
            ),
          ),
        ],
      );
    }
    final pending = widget.pending;
    final (label, tone) = switch (pending) {
      AgentProviderPendingSecret(clears: true) => (
        'Cleared On Save',
        AleraBadgeTone.attention,
      ),
      AgentProviderPendingSecret() => ('Saved On Save', AleraBadgeTone.info),
      null when widget.saved => ('Saved', AleraBadgeTone.success),
      null => ('Not Set', AleraBadgeTone.neutral),
    };
    return Row(
      mainAxisAlignment: .end,
      children: <Widget>[
        AleraBadge(label: label, tone: tone, icon: AleraIcons.secure),
        const Spacer(),
        if (pending != null)
          TextButton(
            onPressed: widget.enabled ? widget.onUndo : null,
            child: const Text('Undo'),
          )
        else ...<Widget>[
          if (widget.saved)
            TextButton(
              onPressed: widget.enabled ? widget.onClear : null,
              child: const Text('Clear'),
            ),
          const SizedBox(width: AleraTokens.space4),
          OutlinedButton(
            onPressed: widget.enabled
                ? () => setState(() => _editing = true)
                : null,
            child: Text(widget.saved ? 'Replace' : 'Set'),
          ),
        ],
      ],
    );
  }
}
