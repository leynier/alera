import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:flutter/material.dart';

/// Prompts for a new mobile device display name; pops with the entered name.
class MobileDeviceRenameDialog extends StatefulWidget {
  const MobileDeviceRenameDialog({super.key, required this.initialName});

  final String initialName;

  @override
  State<MobileDeviceRenameDialog> createState() =>
      _MobileDeviceRenameDialogState();
}

class _MobileDeviceRenameDialogState extends State<MobileDeviceRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: 380,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Rename Device',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space16),
            AleraTextField(
              controller: _controller,
              labelText: 'Device Name',
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Rename'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
