import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:flutter/material.dart';

/// Asks for a pull request number or URL and pops with the trimmed value.
Future<String?> showLinkPullRequestDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _LinkPullRequestDialog(),
  );
}

class const _LinkPullRequestDialog() extends StatefulWidget {
  @override
  State<_LinkPullRequestDialog> createState() => _LinkPullRequestDialogState();
}

class _LinkPullRequestDialogState extends State<_LinkPullRequestDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reference = _controller.text.trim();
    if (reference.isNotEmpty) {
      Navigator.of(context).pop(reference);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Text('Link Pull Request', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _controller,
              autofocus: true,
              labelText: 'Pull Request',
              helperText: 'A number like #123 or a pull request URL.',
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Link'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [CreatePullRequestSheet].
Future<void> showCreatePullRequestSheet(
  BuildContext context, {
  required String? headBranch,
  required List<String> baseBranches,
  required String? suggestedBaseBranch,
  required Future<String?> Function(MobilePullRequestCreateInput input)
  onSubmit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CreatePullRequestSheet(
      headBranch: headBranch,
      baseBranches: baseBranches,
      suggestedBaseBranch: suggestedBaseBranch,
      onSubmit: onSubmit,
    ),
  );
}

/// Form for a new pull request from the workspace branch. Like the comment
/// composer, it keeps its fields while [onSubmit] runs and shows the error
/// inline.
class const CreatePullRequestSheet({
  super.key,
  required final String? headBranch,
  required final List<String> baseBranches,
  required final String? suggestedBaseBranch,
  required final Future<String?> Function(MobilePullRequestCreateInput input)
  onSubmit,
}) extends StatefulWidget {
  @override
  State<CreatePullRequestSheet> createState() => _CreatePullRequestSheetState();
}

class _CreatePullRequestSheetState extends State<CreatePullRequestSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  late String? _base = _initialBase();
  bool _draft = false;
  bool _submitting = false;
  String? _error;

  List<String> get _bases => <String>[
    for (final branch in widget.baseBranches)
      if (branch != widget.headBranch) branch,
  ];

  String? _initialBase() {
    final suggested = widget.suggestedBaseBranch;
    if (suggested != null && _bases.contains(suggested)) {
      return suggested;
    }
    return _bases.isEmpty ? null : _bases.first;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final base = _base;
    final title = _title.text.trim();
    if (base == null || title.isEmpty || _submitting) {
      setState(
        () => _error = base == null
            ? 'Select a base branch.'
            : title.isEmpty
            ? 'Enter a title.'
            : _error,
      );
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.onSubmit((
      baseBranch: base,
      title: title,
      body: _body.text,
      draft: _draft,
    ));
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
    final head = widget.headBranch;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
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
              Text('Create Pull Request', style: theme.textTheme.titleMedium),
              if (head != null) ...<Widget>[
                const SizedBox(height: AleraTokens.space4),
                Text(
                  'From $head',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: AleraTokens.monoStyle.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
              const SizedBox(height: AleraTokens.space12),
              const AleraNotice(
                icon: AleraIcons.info,
                message: 'The branch must already be pushed to GitHub from the paired computer.',
              ),
              const SizedBox(height: AleraTokens.space12),
              AleraDropdownField<String>(
                labelText: 'Base Branch',
                hintText: 'Select a base branch',
                value: _base,
                filterable: true,
                enabled: !_submitting,
                entries: <AleraDropdownFieldEntry<String>>[
                  for (final branch in _bases)
                    AleraDropdownFieldEntry<String>(
                      value: branch,
                      label: branch,
                    ),
                ],
                onChanged: (branch) => setState(() => _base = branch),
              ),
              const SizedBox(height: AleraTokens.space12),
              AleraTextField(
                controller: _title,
                labelText: 'Title',
                enabled: !_submitting,
              ),
              const SizedBox(height: AleraTokens.space12),
              AleraTextField(
                controller: _body,
                labelText: 'Description',
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: 8,
                enabled: !_submitting,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Create As Draft'),
                value: _draft,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _draft = value),
              ),
              if (_error case final error?) ...<Widget>[
                Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.error,
                  ),
                ),
                const SizedBox(height: AleraTokens.space12),
              ],
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
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: AleraTokens.iconSm,
                              child: CircularProgressIndicator(
                                strokeWidth: AleraTokens.strokeMd,
                              ),
                            )
                          : const Icon(AleraIcons.gitPullRequest),
                      label: const Text(
                        'Create Pull Request',
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
