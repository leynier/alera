import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:flutter/material.dart';

/// Opens [ShipPullRequestSheet].
Future<void> showShipPullRequestSheet(
  BuildContext context, {
  required String? headBranch,
  required List<String> baseBranches,
  required String? suggestedBaseBranch,
  required Future<String?> Function(MobilePullRequestShipInput input) onSubmit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ShipPullRequestSheet(
      headBranch: headBranch,
      baseBranches: baseBranches,
      suggestedBaseBranch: suggestedBaseBranch,
      onSubmit: onSubmit,
    ),
  );
}

/// The phone's Ship: pick the base branch and what to commit, and the runtime
/// does the rest. It keeps the choices while [onSubmit] runs and shows the
/// error inline, like the other pull request sheets.
class const ShipPullRequestSheet({
  super.key,
  required final String? headBranch,
  required final List<String> baseBranches,
  required final String? suggestedBaseBranch,
  required final Future<String?> Function(MobilePullRequestShipInput input)
  onSubmit,
}) extends StatefulWidget {
  @override
  State<ShipPullRequestSheet> createState() => _ShipPullRequestSheetState();
}

class _ShipPullRequestSheetState extends State<ShipPullRequestSheet> {
  late String? _base = _initialBase();
  bool _stagedOnly = false;
  bool _draft = false;
  bool _submitting = false;
  String? _error;

  String? _initialBase() {
    final suggested = widget.suggestedBaseBranch;
    if (suggested != null && widget.baseBranches.contains(suggested)) {
      return suggested;
    }
    return widget.baseBranches.isEmpty ? null : widget.baseBranches.first;
  }

  Future<void> _submit() async {
    final base = _base;
    if (_submitting) {
      return;
    }
    if (base == null) {
      setState(() => _error = 'Select a base branch.');
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
      draft: _draft,
      stagedOnly: _stagedOnly,
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
              Text('Ship Changes', style: theme.textTheme.titleMedium),
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
                message: 'Ship commits with an AI Assist message, pushes the branch, and opens a pull request on GitHub. On the base branch it moves the work to a new branch first.',
              ),
              const SizedBox(height: AleraTokens.space12),
              AleraDropdownField<String>(
                labelText: 'Base Branch',
                hintText: 'Select a base branch',
                value: _base,
                filterable: true,
                enabled: !_submitting,
                entries: <AleraDropdownFieldEntry<String>>[
                  for (final branch in widget.baseBranches)
                    AleraDropdownFieldEntry<String>(
                      value: branch,
                      label: branch,
                    ),
                ],
                onChanged: (branch) => setState(() => _base = branch),
              ),
              const SizedBox(height: AleraTokens.space12),
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: false, label: Text('All Changes')),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Staged Changes'),
                  ),
                ],
                selected: <bool>{_stagedOnly},
                onSelectionChanged: _submitting
                    ? null
                    : (selection) =>
                          setState(() => _stagedOnly = selection.first),
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
                        'Ship',
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
