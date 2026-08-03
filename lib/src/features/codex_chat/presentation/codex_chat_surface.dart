import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:path/path.dart' as p;

part 'codex_chat_surface_composer.dart';
part 'codex_chat_surface_timeline.dart';

class CodexChatSurface extends ConsumerStatefulWidget {
  const CodexChatSurface({
    super.key,
    required this.workspace,
    required this.tab,
    this.autofocus = false,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final bool autofocus;

  @override
  ConsumerState<CodexChatSurface> createState() => _CodexChatSurfaceState();
}

class _CodexChatSurfaceState extends ConsumerState<CodexChatSurface> {
  late final TextEditingController _composer;
  late final FocusNode _composerFocus;
  final ScrollController _timeline = ScrollController();
  final List<CodexInputAttachment> _attachments = <CodexInputAttachment>[];
  final TerminalClipboard _clipboard = const NativeTerminalClipboard();
  bool _showRawLogs = false;

  @override
  void initState() {
    super.initState();
    _composer = TextEditingController();
    _composerFocus = FocusNode();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composerFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(codexChatControllerProvider(widget.tab.id));
    final controller = ref.read(
      codexChatControllerProvider(widget.tab.id).notifier,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CodexHeader(
            state: state,
            onModelChanged: controller.setModel,
            onReasoningChanged: controller.setReasoning,
            onSpeedChanged: controller.setSpeed,
            onPermissionChanged: controller.setPermissionMode,
            onPlanChanged: controller.setPlanMode,
            onCompact: controller.compact,
            onReview: controller.startReview,
            onRename: () => _rename(context, controller),
            onInsertToken: _insertComposerToken,
            onToggleRawLogs: () => setState(() => _showRawLogs = !_showRawLogs),
          ),
          const Divider(height: 1, color: AleraTokens.borderSubtle),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.error != null && state.snapshot.events.isEmpty
                ? _CodexFailure(
                    message: state.error!,
                    onRetry: controller.retry,
                  )
                : _CodexTimeline(
                    snapshot: state.snapshot,
                    showRawLogs: _showRawLogs,
                    timeline: _timeline,
                    onApproval: controller.respondApproval,
                    onQuestion: controller.respondQuestion,
                    onImplementPlan: controller.implementPlan,
                  ),
          ),
          if (state.error != null)
            _CodexInlineError(message: state.error!, onRetry: controller.retry),
          if (state.queuedMessages.isNotEmpty)
            _CodexQueueBar(
              messages: state.queuedMessages,
              onRemove: controller.removeQueuedMessage,
            ),
          _CodexComposer(
            controller: _composer,
            focusNode: _composerFocus,
            busy: state.busy,
            interrupting: state.interrupting,
            attachments: _attachments,
            onSend: () => _send(controller),
            onSteer: () => _steer(controller),
            onStop: controller.stop,
            onPaste: _pasteText,
            onRemoveAttachment: _removeAttachment,
          ),
        ],
      ),
    );
  }

  Future<void> _send(CodexChatController controller) async {
    final text = _composer.text;
    final attachments = List<CodexInputAttachment>.of(_attachments);
    _composer.clear();
    _attachments.clear();
    await controller.send(text, attachments: attachments);
    if (mounted) _composerFocus.requestFocus();
  }

  Future<void> _steer(CodexChatController controller) async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await controller.steer(text);
    if (mounted) _composerFocus.requestFocus();
  }

  Future<void> _pasteText() async {
    try {
      final paths = await _clipboard.readFilePaths();
      if (paths.isNotEmpty) {
        setState(() {
          _attachments.addAll(
            paths.map(
              (path) =>
                  CodexInputAttachment(path: path, isImage: _isImagePath(path)),
            ),
          );
        });
        return;
      }
    } catch (_) {
      // Text and image clipboard formats remain available below.
    }
    final text = await _clipboard.readText();
    if (text != null && text.isNotEmpty) {
      final selection = _composer.selection;
      _composer.text = selection.isValid
          ? (_composer.text.replaceRange(selection.start, selection.end, text))
          : '${_composer.text}$text';
      _composer.selection = TextSelection.collapsed(
        offset: _composer.text.length,
      );
      return;
    }
    try {
      final imagePath = await _clipboard.saveImageAsTempFile();
      if (imagePath != null && imagePath.isNotEmpty && mounted) {
        setState(() {
          _attachments.add(
            CodexInputAttachment(path: imagePath, isImage: true),
          );
        });
      }
    } catch (_) {
      // Image clipboard support is optional on platforms without the native
      // clipboard bridge.
    }
  }

  void _removeAttachment(CodexInputAttachment attachment) {
    setState(() => _attachments.remove(attachment));
  }

  void _insertComposerToken(String token) {
    final current = _composer.text.trimRight();
    _composer.text = current.isEmpty ? token : '$current $token';
    _composer.selection = TextSelection.collapsed(
      offset: _composer.text.length,
    );
    _composerFocus.requestFocus();
  }

  Future<void> _rename(
    BuildContext context,
    CodexChatController controller,
  ) async {
    final input = TextEditingController(text: widget.tab.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Codex Thread'),
        content: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name != null) await controller.rename(name);
  }
}

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp');
}

class _CodexHeader extends StatelessWidget {
  const _CodexHeader({
    required this.state,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onSpeedChanged,
    required this.onPermissionChanged,
    required this.onPlanChanged,
    required this.onCompact,
    required this.onReview,
    required this.onRename,
    required this.onInsertToken,
    required this.onToggleRawLogs,
  });

  final CodexChatState state;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String> onReasoningChanged;
  final ValueChanged<String> onSpeedChanged;
  final ValueChanged<String> onPermissionChanged;
  final ValueChanged<bool> onPlanChanged;
  final Future<void> Function() onCompact;
  final Future<void> Function() onReview;
  final VoidCallback onRename;
  final ValueChanged<String> onInsertToken;
  final VoidCallback onToggleRawLogs;

  @override
  Widget build(BuildContext context) {
    final model = state.selectedModel ?? state.models.firstOrNull?.id;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      child: Wrap(
        spacing: AleraTokens.space8,
        runSpacing: AleraTokens.space4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          DropdownButton<String>(
            value: state.models.any((item) => item.id == model) ? model : null,
            hint: const Text('Model'),
            dropdownColor: AleraTokens.surfaceElevated,
            underline: const SizedBox.shrink(),
            items: <DropdownMenuItem<String>>[
              for (final option in state.models)
                DropdownMenuItem<String>(
                  value: option.id,
                  child: Text(option.label),
                ),
            ],
            onChanged: onModelChanged,
          ),
          _CodexCatalogButton(
            label: 'Skills',
            prefix: '/skill ',
            items: state.skills,
            onSelected: onInsertToken,
          ),
          _CodexCatalogButton(
            label: 'Apps',
            prefix: '/app ',
            items: state.apps,
            onSelected: onInsertToken,
          ),
          _CodexCatalogButton(
            label: 'Mentions',
            prefix: '@',
            items: state.apps,
            onSelected: onInsertToken,
          ),
          _CodexChoiceButton(
            label: 'Reasoning: ${_choiceLabel(state.reasoningEffort)}',
            values: const <String>['low', 'medium', 'high', 'xhigh'],
            value: state.reasoningEffort,
            onChanged: onReasoningChanged,
          ),
          _CodexChoiceButton(
            label: 'Speed: ${_choiceLabel(state.speedMode)}',
            values: const <String>['normal', 'fast'],
            value: state.speedMode,
            onChanged: onSpeedChanged,
          ),
          _CodexChoiceButton(
            label: 'Permission: ${_choiceLabel(state.permissionMode)}',
            values: const <String>['on-request', 'never'],
            value: state.permissionMode,
            onChanged: onPermissionChanged,
          ),
          FilterChip(
            label: const Text('Plan'),
            selected: state.planMode,
            onSelected: onPlanChanged,
          ),
          AleraIconButton(
            tooltip: 'Compact Context',
            icon: AleraIcons.collapseAll,
            onPressed: () => unawaited(onCompact()),
          ),
          AleraIconButton(
            tooltip: 'Start Review',
            icon: AleraIcons.checks,
            onPressed: () => unawaited(onReview()),
          ),
          AleraIconButton(
            tooltip: 'Rename Thread',
            icon: AleraIcons.edit,
            onPressed: onRename,
          ),
          AleraIconButton(
            tooltip: 'Raw Logs',
            icon: AleraIcons.file,
            onPressed: onToggleRawLogs,
          ),
        ],
      ),
    );
  }
}

String _choiceLabel(String value) {
  return value
      .split('-')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

class _CodexChoiceButton extends StatelessWidget {
  const _CodexChoiceButton({
    required this.label,
    required this.values,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<String> values;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: onChanged,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        for (final item in values)
          PopupMenuItem<String>(value: item, child: Text(_choiceLabel(item))),
      ],
      child: TextButton.icon(
        onPressed: null,
        icon: const Icon(AleraIcons.chevronDown, size: 14),
        label: Text(label),
      ),
    );
  }
}

class _CodexCatalogButton extends StatelessWidget {
  const _CodexCatalogButton({
    required this.label,
    required this.prefix,
    required this.items,
    required this.onSelected,
  });

  final String label;
  final String prefix;
  final List<Map<String, Object?>> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: items.isNotEmpty,
      tooltip: label,
      onSelected: (name) => onSelected('$prefix$name'),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        for (final item in items)
          if (item['name']?.toString().trim() case final String name
              when name.isNotEmpty)
            PopupMenuItem<String>(value: name, child: Text(name)),
      ],
      child: TextButton.icon(
        onPressed: null,
        icon: const Icon(AleraIcons.chevronDown, size: 14),
        label: Text(label),
      ),
    );
  }
}
