import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Opens [PullRequestCommentSheet] for a new comment, a thread reply, or an
/// edit.
Future<void> showPullRequestCommentSheet(
  BuildContext context, {
  required String title,
  required String submitLabel,
  String initialText = '',
  required Future<String?> Function(String body) onSubmit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PullRequestCommentSheet(
      title: title,
      submitLabel: submitLabel,
      initialText: initialText,
      onSubmit: onSubmit,
    ),
  );
}

/// Composer for a pull request comment. It stays open while [onSubmit] runs
/// and shows the error inline, so a failed post never loses the text; when the
/// sheet was dismissed first, the error goes to the snack bar instead.
class const PullRequestCommentSheet({
  super.key,
  required final String title,
  required final String submitLabel,
  final String initialText = '',
  required final Future<String?> Function(String body) onSubmit,
}) extends StatefulWidget {
  @override
  State<PullRequestCommentSheet> createState() =>
      _PullRequestCommentSheetState();
}

class _PullRequestCommentSheetState extends State<PullRequestCommentSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _controller.text;
    if (body.trim().isEmpty || _submitting) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.onSubmit(body);
    if (!mounted) {
      if (error != null) {
        messenger?.showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    if (error == null) {
      navigator.pop();
      return;
    }
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space16,
            0,
            AleraTokens.space16,
            AleraTokens.space16,
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Text(widget.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: AleraTokens.space12),
              AleraTextField(
                controller: _controller,
                autofocus: true,
                hintText: 'Write a comment',
                keyboardType: TextInputType.multiline,
                minLines: 4,
                maxLines: 10,
                enabled: !_submitting,
                errorText: _error,
              ),
              const SizedBox(height: AleraTokens.space12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: AleraTokens.iconSm,
                              child: CircularProgressIndicator(
                                strokeWidth: AleraTokens.strokeMd,
                              ),
                            )
                          : const Icon(AleraIcons.send),
                      label: Text(
                        widget.submitLabel,
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
