import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_prompt.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_field_overlay.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_field_decoration.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_link_form.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'pull_request_composer_actions.dart';
part 'pull_request_composer_form.dart';

/// User-entered result of the inline create-pull-request form.
class const CreateReviewDraft({
  required final String title,
  required final String baseBranch,
  required final String? body,
  required final bool draft,
});

enum _ComposerMode { create, link }

/// Inline create / link form for the Checks panel when no review is linked.
class const PullRequestComposer({
  super.key,
  required final String repoPath,
  required final String? headBranch,
  required final List<String> baseBranches,
  required final String suggestedBaseBranch,
  required final bool canCreate,
  required final bool busy,
  required final HostedReview? suggestedReview,
  required final PullRequestCreateAction createAction,
  required final ValueChanged<CreateReviewDraft> onCreate,
  required final ValueChanged<String> onLink,
  required final ValueChanged<PullRequestCreateAction> onCreateActionChanged,
  final bool canCreateStack = false,
  final bool creatingStack = false,
  final Future<void> Function(CreateReviewDraft draft)? onCreateStack,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<PullRequestComposer> createState() =>
      _PullRequestComposerState();
}

class _PullRequestComposerState extends ConsumerState<PullRequestComposer> {
  late _ComposerMode _mode;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _linkController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _bodyFocusNode;
  late String _baseBranch;
  String? _errorText;
  bool _generating = false;
  int _generationId = 0;
  late final AiAssistService _aiAssistService;

  @override
  void initState() {
    super.initState();
    _aiAssistService = ref.read(aiAssistServiceProvider);
    _mode = widget.canCreate ? _ComposerMode.create : _ComposerMode.link;
    _titleController = TextEditingController(text: widget.headBranch ?? '');
    _bodyController = TextEditingController();
    _linkController = TextEditingController();
    _titleFocusNode = FocusNode();
    _bodyFocusNode = FocusNode();
    _baseBranch = _resolveBaseBranch(widget.suggestedBaseBranch);
  }

  @override
  void didUpdateWidget(covariant PullRequestComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.canCreate && _mode == _ComposerMode.create) {
      _mode = _ComposerMode.link;
    }
    if (oldWidget.suggestedBaseBranch != widget.suggestedBaseBranch ||
        oldWidget.baseBranches != widget.baseBranches) {
      if (!widget.baseBranches.contains(_baseBranch)) {
        _baseBranch = _resolveBaseBranch(widget.suggestedBaseBranch);
      }
    }
    if (oldWidget.repoPath != widget.repoPath && _generating) {
      _aiAssistService.cancel(oldWidget.repoPath, .pullRequestDetails);
      _generationId += 1;
      _generating = false;
    }
  }

  @override
  void dispose() {
    if (_generating) {
      _aiAssistService.cancel(widget.repoPath, .pullRequestDetails);
    }
    _titleController.dispose();
    _bodyController.dispose();
    _linkController.dispose();
    _titleFocusNode.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  String _resolveBaseBranch(String suggested) {
    if (widget.baseBranches.contains(suggested)) {
      return suggested;
    }
    if (widget.baseBranches.isNotEmpty) {
      return widget.baseBranches.first;
    }
    return suggested.isEmpty ? 'main' : suggested;
  }

  List<AleraDropdownFieldEntry<String>> get _baseEntries {
    final names = widget.baseBranches.isEmpty
        ? <String>[_baseBranch]
        : widget.baseBranches;
    return <AleraDropdownFieldEntry<String>>[
      for (final name in names)
        AleraDropdownFieldEntry<String>(value: name, label: name),
    ];
  }

  CreateReviewDraft? _validatedCreateDraft() {
    final title = _titleController.text.trim();
    final base = _baseBranch.trim();
    if (title.isEmpty) {
      setState(() => _errorText = 'Title is required');
      return null;
    }
    if (base.isEmpty) {
      setState(() => _errorText = 'Base branch is required');
      return null;
    }
    final body = _bodyController.text.trim();
    setState(() => _errorText = null);
    return CreateReviewDraft(
      title: title,
      baseBranch: base,
      body: body.isEmpty ? null : body,
      draft: widget.createAction == PullRequestCreateAction.draft,
    );
  }

  void _submitCreate() {
    final draft = _validatedCreateDraft();
    if (draft != null) {
      widget.onCreate(draft);
    }
  }

  Future<void> _submitCreateStack() async {
    final callback = widget.onCreateStack;
    if (callback == null) {
      return;
    }
    final draft = _validatedCreateDraft();
    if (draft != null) {
      await callback(draft);
    }
  }

  void _submitLink() {
    final value = _linkController.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = 'Enter a PR number or URL');
      return;
    }
    setState(() => _errorText = null);
    widget.onLink(value);
  }

  void _switchMode(_ComposerMode mode) {
    if (_mode == mode) {
      return;
    }
    setState(() {
      _mode = mode;
      _errorText = null;
    });
  }

  Future<void> _generateDetails() async {
    final settings = ref.read(settingsControllerProvider).aiAssist;
    if (_generating ||
        !widget.canCreate ||
        widget.busy ||
        !settings.enabled ||
        _baseBranch.trim().isEmpty) {
      return;
    }
    final requestPath = widget.repoPath;
    final generationId = _generationId + 1;
    final initialTitle = _titleController.text;
    final initialBody = _bodyController.text;
    setState(() {
      _generationId = generationId;
      _generating = true;
      _errorText = null;
    });
    try {
      final result = await _aiAssistService.generate(
        AiAssistRequest(
          operation: .pullRequestDetails,
          workspacePath: requestPath,
          settings: settings,
          baseBranch: _baseBranch,
          headBranch: widget.headBranch,
        ),
      );
      if (!mounted ||
          !_isCurrentGeneration(
            workspacePath: requestPath,
            generationId: generationId,
          )) {
        return;
      }
      if (_titleController.text == initialTitle &&
          _bodyController.text == initialBody) {
        final parsed = parseGeneratedPullRequestDetails(result.text);
        _titleController.text = parsed.title;
        _bodyController.text = parsed.body ?? '';
        _titleController.selection = TextSelection.collapsed(
          offset: _titleController.text.length,
        );
        setState(() {});
        AleraToast.show(
          context,
          message: 'Pull request details generated with ${result.agentLabel}',
          tone: .success,
        );
      } else {
        AleraToast.show(
          context,
          message:
              'Generated details were not applied because the fields changed.',
          tone: .info,
        );
      }
    } on AiAssistCanceledException {
      return;
    } catch (error) {
      if (_isCurrentGeneration(
        workspacePath: requestPath,
        generationId: generationId,
      )) {
        AleraToast.show(context, message: error.toString(), tone: .error);
      }
    } finally {
      if (_isCurrentGeneration(
        workspacePath: requestPath,
        generationId: generationId,
      )) {
        setState(() => _generating = false);
      }
    }
  }

  bool _isCurrentGeneration({
    required String workspacePath,
    required int generationId,
  }) {
    return mounted &&
        widget.repoPath == workspacePath &&
        _generationId == generationId;
  }

  void _cancelGenerate() {
    _aiAssistService.cancel(widget.repoPath, .pullRequestDetails);
  }

  void _update(VoidCallback callback) => setState(callback);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiEnabled = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.aiAssist.enabled,
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                if (_mode == _ComposerMode.link) ...<Widget>[
                  Text(
                    'Link Pull Request',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space16),
                ],
                if (_mode == _ComposerMode.create)
                  _buildCreateForm(theme, aiEnabled: aiEnabled)
                else
                  PullRequestLinkForm(
                    controller: _linkController,
                    busy: widget.busy,
                    suggestedReview: widget.suggestedReview,
                    onChanged: () {
                      if (_errorText != null) {
                        setState(() => _errorText = null);
                      }
                    },
                    onSubmitted: _submitLink,
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
                const SizedBox(height: AleraTokens.space16),
                if (_mode == _ComposerMode.create)
                  _CreatePullRequestButton(
                    action: widget.createAction,
                    busy: widget.busy,
                    enabled: !widget.busy && widget.canCreate && !_generating,
                    onPressed: _submitCreate,
                    onSelected: widget.onCreateActionChanged,
                  )
                else
                  FilledButton.icon(
                    onPressed: widget.busy ? null : _submitLink,
                    icon: widget.busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(AleraIcons.link, size: 16),
                    label: const Text('Link'),
                  ),
                if (widget.canCreateStack &&
                    widget.onCreateStack != null) ...<Widget>[
                  const SizedBox(height: AleraTokens.space8),
                  OutlinedButton.icon(
                    onPressed: widget.busy || _generating
                        ? null
                        : () => unawaited(_submitCreateStack()),
                    icon: widget.creatingStack
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(AleraIcons.gitGraph, size: 16),
                    label: const Text('Create Stack'),
                  ),
                ],
              ],
            ),
          ),
          if (_mode == _ComposerMode.create) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            TextButton(
              onPressed: widget.busy || _generating
                  ? null
                  : () => _switchMode(.link),
              child: const Text('Link Existing Pull Request'),
            ),
          ] else if (widget.canCreate) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            TextButton(
              onPressed: widget.busy ? null : () => _switchMode(.create),
              child: const Text('Create Pull Request'),
            ),
          ],
        ],
      ),
    );
  }
}
