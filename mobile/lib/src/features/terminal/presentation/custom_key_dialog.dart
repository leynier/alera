import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_shortcut_builder.dart';
import 'package:flutter/material.dart';

class CustomKeySelection {
  const CustomKeySelection({required this.key, required this.modifiers});

  final String key;
  final Set<TerminalShortcutModifier> modifiers;
}

/// Picker for a custom quick key: a special key or single character plus
/// Ctrl/Alt/Shift toggles, with a live preview of the resulting label.
Future<CustomKeySelection?> showCustomKeyDialog(BuildContext context) {
  return showDialog<CustomKeySelection>(
    context: context,
    builder: (_) => const _CustomKeyDialog(),
  );
}

class _CustomKeyDialog extends StatefulWidget {
  const _CustomKeyDialog();

  @override
  State<_CustomKeyDialog> createState() => _CustomKeyDialogState();
}

class _CustomKeyDialogState extends State<_CustomKeyDialog> {
  final TextEditingController _character = TextEditingController();
  String? _specialKey;
  final Set<TerminalShortcutModifier> _modifiers = <TerminalShortcutModifier>{};

  @override
  void dispose() {
    _character.dispose();
    super.dispose();
  }

  String? get _selectedKey {
    if (_specialKey != null) {
      return _specialKey;
    }
    final text = _character.text.trim();
    return text.isEmpty ? null : text.substring(0, 1);
  }

  TerminalShortcutBuildResult? get _preview {
    final key = _selectedKey;
    if (key == null) {
      return null;
    }
    return buildTerminalShortcutKey(
      TerminalShortcutBinding(key: key, modifiers: _modifiers),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('Add Custom Key'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DropdownButtonFormField<String?>(
              initialValue: _specialKey,
              decoration: const InputDecoration(labelText: 'Special Key'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Character Below'),
                ),
                for (final id in terminalShortcutSpecialKeys)
                  DropdownMenuItem<String?>(
                    value: id,
                    child: Text(terminalShortcutSpecialKeyLabel(id)),
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  _specialKey = value;
                });
              },
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            TextField(
              controller: _character,
              enabled: _specialKey == null,
              maxLength: 1,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Character',
                counterText: '',
              ),
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            Wrap(
              spacing: AleraTokens.spaceSm,
              children: <Widget>[
                for (final modifier in TerminalShortcutModifier.values)
                  FilterChip(
                    label: Text(switch (modifier) {
                      TerminalShortcutModifier.ctrl => 'Ctrl',
                      TerminalShortcutModifier.alt => 'Alt',
                      TerminalShortcutModifier.shift => 'Shift',
                    }),
                    selected: _modifiers.contains(modifier),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _modifiers.add(modifier);
                        } else {
                          _modifiers.remove(modifier);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            Text(
              preview == null ? 'Pick A Key' : preview.label,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontFamily: AleraTokens.monoFontFamily),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: preview == null
              ? null
              : () => Navigator.of(context).pop(
                  CustomKeySelection(
                    key: _selectedKey!,
                    modifiers: <TerminalShortcutModifier>{..._modifiers},
                  ),
                ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
