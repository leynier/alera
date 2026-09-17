import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/workbench/presentation/background_submission.dart';
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

/// Submits comments in the background and retains their text for recovery.
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
    _submitting = true;
    final form = widget;
    submitInBackground(
      context,
      title: form.title,
      action: () => form.onSubmit(body),
      restoreForm: (_) => PullRequestCommentSheet(
        title: form.title,
        submitLabel: form.submitLabel,
        initialText: body,
        onSubmit: form.onSubmit,
      ),
    );
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
