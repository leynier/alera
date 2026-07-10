import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// The user-entered result of the create-pull-request dialog.
class CreateReviewDraft {
  const CreateReviewDraft({
    required this.title,
    required this.baseBranch,
    required this.body,
    required this.draft,
  });

  final String title;
  final String baseBranch;
  final String? body;
  final bool draft;
}

/// Collects the title, base branch, body, and draft flag for a new review.
Future<CreateReviewDraft?> showCreateReviewDialog(
  BuildContext context, {
  required String defaultTitle,
  required String defaultBaseBranch,
  required String headBranch,
}) {
  return showDialog<CreateReviewDraft>(
    context: context,
    builder: (context) => _CreateReviewDialog(
      defaultTitle: defaultTitle,
      defaultBaseBranch: defaultBaseBranch,
      headBranch: headBranch,
    ),
  );
}

class _CreateReviewDialog extends StatefulWidget {
  const _CreateReviewDialog({
    required this.defaultTitle,
    required this.defaultBaseBranch,
    required this.headBranch,
  });

  final String defaultTitle;
  final String defaultBaseBranch;
  final String headBranch;

  @override
  State<_CreateReviewDialog> createState() => _CreateReviewDialogState();
}

class _CreateReviewDialogState extends State<_CreateReviewDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _baseController;
  late final TextEditingController _bodyController;
  bool _draft = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.defaultTitle);
    _baseController = TextEditingController(text: widget.defaultBaseBranch);
    _bodyController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _baseController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final base = _baseController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = 'Title Is Required');
      return;
    }
    if (base.isEmpty) {
      setState(() => _errorText = 'Base Branch Is Required');
      return;
    }
    final body = _bodyController.text.trim();
    Navigator.of(context).pop(
      CreateReviewDraft(
        title: title,
        baseBranch: base,
        body: body.isEmpty ? null : body,
        draft: _draft,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 520,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Create Pull Request', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space4),
            Text(
              'From ${widget.headBranch}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            _field(theme, _titleController, 'Title', autofocus: true),
            const SizedBox(height: AleraTokens.space12),
            _field(theme, _baseController, 'Base Branch'),
            const SizedBox(height: AleraTokens.space12),
            _field(
              theme,
              _bodyController,
              'Description',
              minLines: 3,
              maxLines: 6,
            ),
            if (_errorText != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                _errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.error,
                ),
              ),
            ],
            const SizedBox(height: AleraTokens.space12),
            Row(
              children: <Widget>[
                AleraCheckbox(
                  value: _draft,
                  onChanged: (value) => setState(() => _draft = value),
                ),
                const SizedBox(width: AleraTokens.space8),
                Text('Create As Draft', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(onPressed: _submit, child: const Text('Create')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    ThemeData theme,
    TextEditingController controller,
    String hint, {
    bool autofocus = false,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      minLines: minLines,
      maxLines: maxLines,
      style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.foreground),
      cursorColor: AleraTokens.foreground,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AleraTokens.surface,
        hintText: hint,
        hintStyle: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundFaint,
        ),
        contentPadding: const EdgeInsets.all(AleraTokens.space12),
      ),
      onChanged: (_) {
        if (_errorText != null) {
          setState(() => _errorText = null);
        }
      },
    );
  }
}
