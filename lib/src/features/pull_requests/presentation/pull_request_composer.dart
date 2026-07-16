import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_prompt.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_providers.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_service.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_field_decoration.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'pull_request_composer_actions.dart';

/// User-entered result of the inline create-pull-request form.
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

enum _ComposerMode { create, link }

/// Inline create / link form for the Checks panel when no review is linked.
class PullRequestComposer extends ConsumerStatefulWidget {
  const PullRequestComposer({
    super.key,
    required this.repoPath,
    required this.headBranch,
    required this.baseBranches,
    required this.suggestedBaseBranch,
    required this.canCreate,
    required this.busy,
    required this.createAction,
    required this.onCreate,
    required this.onLink,
    required this.onCreateActionChanged,
  });

  final String repoPath;
  final String? headBranch;
  final List<String> baseBranches;
  final String suggestedBaseBranch;
  final bool canCreate;
  final bool busy;
  final PullRequestCreateAction createAction;
  final ValueChanged<CreateReviewDraft> onCreate;
  final ValueChanged<String> onLink;
  final ValueChanged<PullRequestCreateAction> onCreateActionChanged;

  @override
  ConsumerState<PullRequestComposer> createState() =>
      _PullRequestComposerState();
}

class _PullRequestComposerState extends ConsumerState<PullRequestComposer> {
  late _ComposerMode _mode;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _linkController;
  late String _baseBranch;
  String? _errorText;
  bool _generating = false;
  int _generationId = 0;
  late final AiTextGenerationService _aiTextGenerationService;

  @override
  void initState() {
    super.initState();
    _aiTextGenerationService = ref.read(aiTextGenerationServiceProvider);
    _mode = widget.canCreate ? _ComposerMode.create : _ComposerMode.link;
    _titleController = TextEditingController(text: widget.headBranch ?? '');
    _bodyController = TextEditingController();
    _linkController = TextEditingController();
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
      _aiTextGenerationService.cancel(
        oldWidget.repoPath,
        AiTextGenerationOperation.pullRequestDetails,
      );
      _generationId += 1;
      _generating = false;
    }
  }

  @override
  void dispose() {
    if (_generating) {
      _aiTextGenerationService.cancel(
        widget.repoPath,
        AiTextGenerationOperation.pullRequestDetails,
      );
    }
    _titleController.dispose();
    _bodyController.dispose();
    _linkController.dispose();
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

  void _submitCreate() {
    final title = _titleController.text.trim();
    final base = _baseBranch.trim();
    if (title.isEmpty) {
      setState(() => _errorText = 'Title Is Required');
      return;
    }
    if (base.isEmpty) {
      setState(() => _errorText = 'Base Branch Is Required');
      return;
    }
    final body = _bodyController.text.trim();
    setState(() => _errorText = null);
    widget.onCreate(
      CreateReviewDraft(
        title: title,
        baseBranch: base,
        body: body.isEmpty ? null : body,
        draft: widget.createAction == PullRequestCreateAction.draft,
      ),
    );
  }

  void _submitLink() {
    final value = _linkController.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = 'Enter A PR Number Or URL');
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
    final settings = ref.read(settingsControllerProvider).aiTextGeneration;
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
      final result = await _aiTextGenerationService.generate(
        AiTextGenerationRequest(
          operation: AiTextGenerationOperation.pullRequestDetails,
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
          tone: AleraToastTone.success,
        );
      } else {
        AleraToast.show(
          context,
          message:
              'Generated details were not applied because the fields changed.',
          tone: AleraToastTone.info,
        );
      }
    } on AiTextGenerationCanceledException {
      return;
    } catch (error) {
      if (_isCurrentGeneration(
        workspacePath: requestPath,
        generationId: generationId,
      )) {
        AleraToast.show(
          context,
          message: error.toString(),
          tone: AleraToastTone.error,
        );
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
    _aiTextGenerationService.cancel(
      widget.repoPath,
      AiTextGenerationOperation.pullRequestDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiEnabled = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.aiTextGeneration.enabled,
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  _buildLinkForm(theme),
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
              ],
            ),
          ),
          if (_mode == _ComposerMode.create) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            TextButton(
              onPressed: widget.busy || _generating
                  ? null
                  : () => _switchMode(_ComposerMode.link),
              child: const Text('Link Existing Pull Request'),
            ),
          ] else if (widget.canCreate) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            TextButton(
              onPressed: widget.busy
                  ? null
                  : () => _switchMode(_ComposerMode.create),
              child: const Text('Create Pull Request'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCreateForm(ThemeData theme, {required bool aiEnabled}) {
    final enabled = !widget.busy && widget.canCreate && !_generating;
    final canGenerate =
        aiEnabled && widget.canCreate && !widget.busy && !_generating;
    final titleField = TextField(
      controller: _titleController,
      enabled: enabled,
      style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.foreground),
      cursorColor: AleraTokens.foreground,
      decoration: pullRequestFieldDecoration(theme, hint: 'Title'),
      onChanged: (_) {
        if (_errorText != null) {
          setState(() => _errorText = null);
        }
      },
    );
    final descriptionField = TextField(
      controller: _bodyController,
      enabled: enabled,
      minLines: 3,
      maxLines: 20,
      style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.foreground),
      cursorColor: AleraTokens.foreground,
      decoration: pullRequestFieldDecoration(theme, hint: 'Description'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AleraDropdownField<String>(
          labelText: 'Base Branch',
          value: _baseBranch,
          enabled: enabled,
          entries: _baseEntries,
          onChanged: (value) {
            setState(() {
              _baseBranch = value;
              _errorText = null;
            });
          },
        ),
        const SizedBox(height: AleraTokens.space12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Title',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ),
            if (aiEnabled || _generating)
              _AiPullRequestButton(
                generating: _generating,
                canGenerate: canGenerate,
                onGenerate: () => unawaited(_generateDetails()),
                onCancel: _cancelGenerate,
              ),
          ],
        ),
        const SizedBox(height: AleraTokens.space4),
        if (_generating) _AiDimmedBlock(child: titleField) else titleField,
        const SizedBox(height: AleraTokens.space12),
        _labeledField(
          theme,
          label: 'Description',
          child: _generating
              ? _AiGeneratingOverlay(child: descriptionField)
              : descriptionField,
        ),
      ],
    );
  }

  Widget _buildLinkForm(ThemeData theme) {
    return _labeledField(
      theme,
      label: 'Pull Request',
      child: TextField(
        controller: _linkController,
        enabled: !widget.busy,
        autofocus: true,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foreground,
        ),
        cursorColor: AleraTokens.foreground,
        decoration: pullRequestFieldDecoration(
          theme,
          hint: '#123 Or Pull Request URL',
        ),
        onChanged: (_) {
          if (_errorText != null) {
            setState(() => _errorText = null);
          }
        },
        onSubmitted: (_) {
          if (!widget.busy) {
            _submitLink();
          }
        },
      ),
    );
  }

  Widget _labeledField(
    ThemeData theme, {
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space4),
        child,
      ],
    );
  }
}
