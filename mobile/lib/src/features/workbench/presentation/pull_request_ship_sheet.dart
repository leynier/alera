import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_source_control.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_ship_follow_up.dart';
import 'package:alera_mobile/src/features/workbench/presentation/background_submission.dart';
import 'package:flutter/material.dart';

/// Whether Ship should ask All vs Staged. A loaded snapshot with no entries
/// ships staged without the choice, matching desktop. A missing snapshot
/// (status unread or failed) keeps the control.
bool shipShowsWorkingTreeScopeChoice(MobileGitStatusSnapshot? snapshot) {
  return snapshot == null || snapshot.entries.isNotEmpty;
}

/// Opens [ShipPullRequestSheet].
Future<void> showShipPullRequestSheet(
  BuildContext context, {
  required String? headBranch,
  required List<String> baseBranches,
  required String? suggestedBaseBranch,
  bool askWorkingTreeScope = true,
  PullRequestShipFollowUp initialFollowUp = PullRequestShipFollowUp.none,
  PullRequestAgentWatchScope initialWatchScope =
      PullRequestAgentWatchScope.defaults,
  Future<AgentTaskDispatchBinding?> Function(PullRequestAgentWatchMode mode)?
  chooseAgent,
  required Future<PullRequestShipOutcome> Function(
    PullRequestShipRequest request,
  )
  onSubmit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ShipPullRequestSheet(
      headBranch: headBranch,
      baseBranches: baseBranches,
      suggestedBaseBranch: suggestedBaseBranch,
      askWorkingTreeScope: askWorkingTreeScope,
      initialFollowUp: initialFollowUp,
      initialWatchScope: initialWatchScope,
      chooseAgent: chooseAgent,
      onSubmit: onSubmit,
    ),
  );
}

/// The phone's Ship: pick the base branch, what to commit, and what to start
/// afterwards, and the runtime does the rest in the background, retaining
/// choices for failure recovery. Without [chooseAgent] the watch follow-ups
/// are hidden.
class const ShipPullRequestSheet({
  super.key,
  required final String? headBranch,
  required final List<String> baseBranches,
  required final String? suggestedBaseBranch,
  final bool askWorkingTreeScope = true,
  final MobilePullRequestShipInput? initialInput,
  final PullRequestShipFollowUp initialFollowUp = PullRequestShipFollowUp.none,
  final PullRequestAgentWatchScope initialWatchScope =
      PullRequestAgentWatchScope.defaults,
  final Future<AgentTaskDispatchBinding?> Function(
    PullRequestAgentWatchMode mode,
  )?
  chooseAgent,
  required final Future<PullRequestShipOutcome> Function(
    PullRequestShipRequest request,
  )
  onSubmit,
}) extends StatefulWidget {
  @override
  State<ShipPullRequestSheet> createState() => _ShipPullRequestSheetState();
}

class _ShipPullRequestSheetState extends State<ShipPullRequestSheet> {
  late String? _base = _initialBase();
  late bool _stagedOnly;
  bool _draft = false;
  late PullRequestShipFollowUp _followUp = widget.chooseAgent == null
      ? PullRequestShipFollowUp.none
      : widget.initialFollowUp;
  late PullRequestAgentWatchScope _watchScope = widget.initialWatchScope;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stagedOnly =
        widget.initialInput?.stagedOnly ?? !widget.askWorkingTreeScope;
    _draft = widget.initialInput?.draft ?? false;
  }

  String? _initialBase() {
    final suggested =
        widget.initialInput?.baseBranch ?? widget.suggestedBaseBranch;
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
    final followUp = _followUp;
    final watchScope = _watchScope;
    if (followUp.watches && watchScope.isEmpty) {
      setState(() => _error = 'Choose at least one problem to watch.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final form = widget;
    AgentTaskDispatchBinding? binding;
    final mode = followUp.watchMode;
    final chooseAgent = form.chooseAgent;
    if (mode != null && chooseAgent != null) {
      // Picked before shipping, so declining the agent commits nothing.
      binding = await chooseAgent(mode);
      if (!mounted) return;
      if (binding == null) {
        setState(() => _submitting = false);
        return;
      }
    }
    final request = (
      input: (
        baseBranch: base,
        draft: _draft && !followUp.merges,
        stagedOnly: _stagedOnly,
      ),
      followUp: followUp,
      watchScope: watchScope,
      binding: binding,
    );
    String? notice;
    submitInBackground(
      context,
      title: 'Ship changes',
      action: () async {
        final outcome = await form.onSubmit(request);
        notice = outcome.notice;
        return outcome.error;
      },
      // A follow-up that failed after the pull request was created must not be
      // followed by a success message, and must not reopen the form either.
      successMessage: () => notice ?? 'Ship changes completed.',
      restoreForm: (_) => ShipPullRequestSheet(
        headBranch: form.headBranch,
        baseBranches: form.baseBranches,
        suggestedBaseBranch: form.suggestedBaseBranch,
        askWorkingTreeScope: form.askWorkingTreeScope,
        initialInput: request.input,
        initialFollowUp: followUp,
        initialWatchScope: watchScope,
        chooseAgent: form.chooseAgent,
        onSubmit: form.onSubmit,
      ),
    );
  }

  String get _shipLabel => switch (_followUp) {
    PullRequestShipFollowUp.none => 'Ship',
    PullRequestShipFollowUp.watchAndFix => 'Ship and Watch',
    PullRequestShipFollowUp.watchFixAndMerge => 'Ship and Merge',
  };

  List<Widget> _followUpFields() {
    void toggle(PullRequestAgentWatchScope next) =>
        setState(() => _watchScope = next);
    return <Widget>[
      const SizedBox(height: AleraTokens.space12),
      AleraDropdownField<PullRequestShipFollowUp>(
        labelText: 'After Shipping',
        value: _followUp,
        enabled: !_submitting,
        entries: <AleraDropdownFieldEntry<PullRequestShipFollowUp>>[
          for (final followUp in PullRequestShipFollowUp.values)
            AleraDropdownFieldEntry<PullRequestShipFollowUp>(
              value: followUp,
              label: followUp.label,
            ),
        ],
        onChanged: (followUp) => setState(() {
          _followUp = followUp;
          _error = null;
        }),
      ),
      if (_followUp.watches) ...<Widget>[
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Failed Checks'),
          value: _watchScope.checks,
          onChanged: _submitting
              ? null
              : (value) => toggle(_watchScope.copyWith(checks: value ?? false)),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Review Comments'),
          value: _watchScope.comments,
          onChanged: _submitting
              ? null
              : (value) =>
                    toggle(_watchScope.copyWith(comments: value ?? false)),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Merge Conflicts'),
          value: _watchScope.conflicts,
          onChanged: _submitting
              ? null
              : (value) =>
                    toggle(_watchScope.copyWith(conflicts: value ?? false)),
        ),
      ],
    ];
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
              if (widget.askWorkingTreeScope) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('All Changes'),
                    ),
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
              ],
              if (widget.chooseAgent != null) ..._followUpFields(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Create As Draft'),
                subtitle: _followUp.merges
                    ? const Text('Merging needs a ready pull request.')
                    : null,
                value: _draft && !_followUp.merges,
                onChanged: _submitting || _followUp.merges
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
                      label: Text(_shipLabel, maxLines: 1, overflow: .ellipsis),
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
