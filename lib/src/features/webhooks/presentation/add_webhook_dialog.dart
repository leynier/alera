import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';
import 'package:flutter/material.dart';

/// Creates the webhook; `kinds` is `null` when every event kind is selected.
typedef WebhookCreator = Future<RuntimeWebhookCreation> Function(
  String url,
  List<String>? kinds,
);

/// Message shown when [WebhookCreator] fails, so the dialog stays open with
/// the user's input instead of losing it.
typedef WebhookErrorFormatter = String Function(Object error);

/// Asks for a webhook URL and its event kinds, then runs [onCreate]. Pops the
/// [RuntimeWebhookCreation] on success so the caller can show the secret once.
class const AddWebhookDialog({
  super.key,
  required final WebhookCreator onCreate,
  required final WebhookErrorFormatter errorMessage,
}) extends StatefulWidget {
  @override
  State<AddWebhookDialog> createState() => _AddWebhookDialogState();
}

class _AddWebhookDialogState extends State<AddWebhookDialog> {
  final TextEditingController _url = TextEditingController();
  final Set<RuntimeEventKind> _kinds = RuntimeEventKind.values.toSet();
  String? _urlError;
  String? _error;
  bool _creating = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  bool get _allKinds => _kinds.length == RuntimeEventKind.values.length;

  Future<void> _submit() async {
    final urlError = webhookUrlError(_url.text);
    if (urlError != null || _kinds.isEmpty) {
      setState(() {
        _urlError = urlError;
        _error = _kinds.isEmpty ? 'Select at least one event.' : null;
      });
      return;
    }
    setState(() {
      _creating = true;
      _urlError = null;
      _error = null;
    });
    try {
      final created = await widget.onCreate(
        _url.text.trim(),
        _allKinds
            ? null
            : <String>[
                for (final kind in RuntimeEventKind.values)
                  if (_kinds.contains(kind)) kind.wireName,
              ],
      );
      if (mounted) {
        Navigator.of(context).pop(created);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = widget.errorMessage(error);
        });
      }
    }
  }

  void _toggleAll(bool selected) {
    setState(() {
      _kinds.clear();
      if (selected) {
        _kinds.addAll(RuntimeEventKind.values);
      }
    });
  }

  void _toggle(RuntimeEventKind kind, bool selected) {
    setState(() => selected ? _kinds.add(kind) : _kinds.remove(kind));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 520,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Add Webhook',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _url,
              autofocus: true,
              enabled: !_creating,
              labelText: 'Webhook URL',
              hintText: 'https://example.com/hooks/alera',
              errorText: _urlError,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) {
                if (_urlError != null) {
                  setState(() => _urlError = null);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space16),
            Text(
              'Events',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foreground,
                fontWeight: .w500,
              ),
            ),
            const SizedBox(height: AleraTokens.space4),
            AleraCheckbox(
              label: 'All Events',
              value: _allKinds,
              enabled: !_creating,
              onChanged: _toggleAll,
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(left: AleraTokens.space16),
                  child: Wrap(
                    spacing: AleraTokens.space8,
                    children: <Widget>[
                      for (final kind in RuntimeEventKind.values)
                        Tooltip(
                          message: kind.wireName,
                          child: AleraCheckbox(
                            label: kind.label,
                            value: _kinds.contains(kind),
                            enabled: !_creating,
                            onChanged: (selected) => _toggle(kind, selected),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_error case final String message) ...<Widget>[
              const SizedBox(height: AleraTokens.space12),
              AleraInlineNotice(tone: .error, message: message),
            ],
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: .end,
              children: <Widget>[
                TextButton(
                  onPressed: _creating
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _creating ? null : _submit,
                  child: Text(_creating ? 'Adding…' : 'Add Webhook'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
