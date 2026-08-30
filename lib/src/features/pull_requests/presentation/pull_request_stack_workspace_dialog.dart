import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_stack_workspace_models.dart';
import 'package:flutter/material.dart';

part 'pull_request_stack_workspace_layer_card.dart';

class const PullRequestStackWorkspaceDialog({
  super.key,
  required final String currentTitle,
  required final bool currentDraft,
  required final List<ReviewStackWorkspaceCandidate> candidates,
  required final List<String> baseBranches,
  required final String suggestedBaseBranch,
  required final bool defaultDraft,
  final String? currentBody,
  final HostedReviewStack? stack,
}) extends StatefulWidget {
  @override
  State<PullRequestStackWorkspaceDialog> createState() =>
      _PullRequestStackWorkspaceDialogState();
}

class _PullRequestStackWorkspaceDialogState
    extends State<PullRequestStackWorkspaceDialog> {
  final List<_WorkspaceLayerDraft> _layers = <_WorkspaceLayerDraft>[];
  String? _workspaceToAdd;
  String? _errorText;
  late String _baseBranch;

  bool get _appending => widget.stack != null;

  @override
  void initState() {
    super.initState();
    _baseBranch = _resolveBaseBranch(widget.suggestedBaseBranch);
    for (final candidate in _initialCandidates()) {
      _layers.add(_draftFor(candidate));
    }
  }

  @override
  void dispose() {
    for (final layer in _layers) {
      layer.dispose();
    }
    super.dispose();
  }

  List<ReviewStackWorkspaceCandidate> get _eligibleCandidates {
    final existingBranches = widget.stack?.entries
        .map((entry) => entry.review.headBranch)
        .whereType<String>()
        .toSet();
    return <ReviewStackWorkspaceCandidate>[
      for (final candidate in widget.candidates)
        if (!(existingBranches?.contains(candidate.branch) ?? false)) candidate,
    ];
  }

  List<ReviewStackWorkspaceCandidate> get _availableCandidates {
    final selectedIds = _layers
        .map((layer) => layer.candidate.workspaceId)
        .toSet();
    return <ReviewStackWorkspaceCandidate>[
      for (final candidate in _eligibleCandidates)
        if (!selectedIds.contains(candidate.workspaceId)) candidate,
    ];
  }

  List<ReviewStackWorkspaceCandidate> _initialCandidates() {
    if (_appending) {
      return const <ReviewStackWorkspaceCandidate>[];
    }
    ReviewStackWorkspaceCandidate? current;
    for (final candidate in _eligibleCandidates) {
      if (candidate.current) {
        current = candidate;
        break;
      }
    }
    if (current == null) {
      return const <ReviewStackWorkspaceCandidate>[];
    }

    final byBranch = <String, ReviewStackWorkspaceCandidate>{
      for (final candidate in _eligibleCandidates) candidate.branch: candidate,
    };
    final byId = <String, ReviewStackWorkspaceCandidate>{
      for (final candidate in _eligibleCandidates)
        candidate.workspaceId: candidate,
    };
    final chain = <ReviewStackWorkspaceCandidate>[current];
    final seen = <String>{current.workspaceId};
    while (true) {
      final first = chain.first;
      final parent =
          byId[first.parentWorkspaceId] ?? byBranch[first.sourceBranch?.trim()];
      if (parent == null || !seen.add(parent.workspaceId)) {
        break;
      }
      chain.insert(0, parent);
    }
    return chain;
  }

  _WorkspaceLayerDraft _draftFor(ReviewStackWorkspaceCandidate candidate) {
    final current = candidate.current;
    return _WorkspaceLayerDraft(
      candidate: candidate,
      title: current ? widget.currentTitle : candidate.branch,
      body: current ? widget.currentBody : null,
      draft: current ? widget.currentDraft : widget.defaultDraft,
    );
  }

  String _resolveBaseBranch(String suggested) {
    final trimmed = suggested.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    if (widget.baseBranches.isNotEmpty) {
      return widget.baseBranches.first;
    }
    return 'main';
  }

  List<AleraDropdownFieldEntry<String>> get _baseEntries {
    final branches = <String>{...widget.baseBranches, _baseBranch}.toList()
      ..sort();
    return <AleraDropdownFieldEntry<String>>[
      for (final branch in branches)
        AleraDropdownFieldEntry<String>(value: branch, label: branch),
    ];
  }

  void _addWorkspace(String? workspaceId) {
    if (workspaceId == null) {
      return;
    }
    ReviewStackWorkspaceCandidate? candidate;
    for (final entry in _availableCandidates) {
      if (entry.workspaceId == workspaceId) {
        candidate = entry;
        break;
      }
    }
    if (candidate == null) {
      return;
    }
    setState(() {
      _layers.add(_draftFor(candidate!));
      _workspaceToAdd = null;
      _errorText = null;
    });
  }

  void _move(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _layers.length) {
      return;
    }
    setState(() {
      final layer = _layers.removeAt(index);
      _layers.insert(target, layer);
    });
  }

  void _remove(int index) {
    final layer = _layers[index];
    if (!_appending && layer.candidate.current) {
      return;
    }
    setState(() {
      _layers.removeAt(index).dispose();
      _errorText = null;
    });
  }

  String _baseForLayer(int index) {
    if (index > 0) {
      return _layers[index - 1].candidate.branch;
    }
    if (_appending) {
      return widget.stack!.entries.last.review.headBranch ??
          widget.stack!.baseBranch;
    }
    return _baseBranch;
  }

  void _submit() {
    if ((!_appending && _layers.length < 2) ||
        (_appending && _layers.isEmpty)) {
      setState(() {
        _errorText = _appending
            ? 'Choose at least one workspace to add.'
            : 'Choose at least two workspaces for the stack.';
      });
      return;
    }
    if (!_appending && !_layers.any((layer) => layer.candidate.current)) {
      setState(() {
        _errorText = 'The current workspace must remain in the stack.';
      });
      return;
    }

    final inputs = <ReviewStackWorkspaceLayerInput>[];
    for (final layer in _layers) {
      final title = layer.titleController.text.trim();
      if (title.isEmpty) {
        setState(() {
          _errorText = 'Enter a title for `${layer.candidate.branch}`.';
        });
        return;
      }
      final body = layer.bodyController.text.trim();
      inputs.add(
        ReviewStackWorkspaceLayerInput(
          workspaceId: layer.candidate.workspaceId,
          repoPath: layer.candidate.repoPath,
          branch: layer.candidate.branch,
          title: title,
          body: body.isEmpty ? null : body,
          draft: layer.draft,
        ),
      );
    }
    Navigator.of(context).pop(
      ReviewStackWorkspaceRequest(
        baseBranch: _appending ? widget.stack!.baseBranch : _baseBranch,
        layers: inputs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = _availableCandidates;
    return AleraDialog(
      maxWidth: 760,
      maxHeight: 760,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: _appending
                  ? 'Add Workspaces To Stack'
                  : 'Create Stack From Workspaces',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space12),
            Text(
              'Order workspaces from the bottom layer to the top. Selected branches are pushed; open pull requests are reused and missing pull requests are created with the details below.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            if (!_appending) ...<Widget>[
              const SizedBox(height: AleraTokens.space16),
              AleraDropdownField<String>(
                labelText: 'Stack Base Branch',
                value: _baseBranch,
                entries: _baseEntries,
                onChanged: (value) => setState(() => _baseBranch = value),
              ),
            ],
            if (available.isNotEmpty) ...<Widget>[
              const SizedBox(height: AleraTokens.space16),
              AleraDropdownField<String?>(
                labelText: 'Add Workspace',
                value: _workspaceToAdd,
                filterable: true,
                filterHintText: 'Search Workspaces',
                entries: <AleraDropdownFieldEntry<String?>>[
                  const AleraDropdownFieldEntry<String?>(
                    value: null,
                    label: 'Choose Workspace',
                  ),
                  for (final candidate in available)
                    AleraDropdownFieldEntry<String?>(
                      value: candidate.workspaceId,
                      label: '${candidate.name} - ${candidate.branch}',
                    ),
                ],
                onChanged: _addWorkspace,
              ),
            ],
            const SizedBox(height: AleraTokens.space16),
            Expanded(
              child: _layers.isEmpty
                  ? Center(
                      child: Text(
                        'No workspaces selected',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _layers.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AleraTokens.space12),
                      itemBuilder: (context, index) => _WorkspaceLayerCard(
                        index: index,
                        total: _layers.length,
                        layer: _layers[index],
                        baseBranch: _baseForLayer(index),
                        removable:
                            _appending || !_layers[index].candidate.current,
                        onMoveUp: () => _move(index, -1),
                        onMoveDown: () => _move(index, 1),
                        onRemove: () => _remove(index),
                        onDraftChanged: (value) =>
                            setState(() => _layers[index].draft = value),
                      ),
                    ),
            ),
            if (_errorText != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space12),
              Text(
                _errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.error,
                ),
              ),
            ],
            const SizedBox(height: AleraTokens.space16),
            Row(
              mainAxisAlignment: .end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _submit,
                  child: Text(_appending ? 'Add Workspaces' : 'Create Stack'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
