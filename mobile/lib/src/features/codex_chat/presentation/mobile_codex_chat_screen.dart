import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

part 'mobile_codex_chat_composer.dart';
part 'mobile_codex_chat_timeline.dart';
part 'mobile_codex_chat_markdown.dart';

class MobileCodexChatScreen extends ConsumerStatefulWidget {
  const MobileCodexChatScreen({
    super.key,
    required this.hostId,
    required this.tabId,
  });

  final String hostId;
  final String tabId;

  @override
  ConsumerState<MobileCodexChatScreen> createState() =>
      _MobileCodexChatScreenState();
}

class _MobileCodexChatScreenState extends ConsumerState<MobileCodexChatScreen> {
  late final TextEditingController _composer;
  late final FocusNode _composerFocus;
  final ScrollController _timeline = ScrollController();
  final List<Map<String, Object?>> _attachments = <Map<String, Object?>>[];

  @override
  void initState() {
    super.initState();
    _composer = TextEditingController();
    _composerFocus = FocusNode();
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
    final provider = mobileCodexControllerProvider(widget.hostId, widget.tabId);
    final value = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    return switch (value) {
      AsyncData(value: final state) => _buildChat(context, state, controller),
      AsyncError(:final error) => _MobileError(
        message: error.toString(),
        onRetry: () => ref.invalidate(provider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _buildChat(
    BuildContext context,
    MobileCodexState state,
    MobileCodexController controller,
  ) {
    _scheduleTimelinePin();
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            controller: _timeline,
            padding: AleraTokens.contentPadding,
            children: <Widget>[
              if (state.timelineCells.isEmpty && state.pendingRequests.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AleraTokens.space32),
                  child: Center(
                    child: Text('Ask Codex to work on this workspace.'),
                  ),
                ),
              for (final cell in state.timelineCells)
                _MobileTimelineCell(cell: cell),
              for (final request in state.pendingRequests)
                if (request.isApproval)
                  _MobileApprovalCard(request: request, controller: controller)
                else if (request.isQuestion)
                  _MobileQuestionCard(request: request, controller: controller)
                else if (request.isElicitation)
                  _MobileElicitationCard(
                    request: request,
                    controller: controller,
                  )
                else
                  _MobileRequestCard(
                    title: 'Codex Request',
                    body: request.method,
                    actions: <Widget>[
                      TextButton(
                        onPressed: () =>
                            unawaited(controller.rejectRequest(request)),
                        child: const Text('Decline'),
                      ),
                    ],
                  ),
              if (state.planMode && state.shouldShowImplementPlan)
                _MobilePlanPrompt(controller: controller),
            ],
          ),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space16,
            ),
            child: MaterialBanner(
              content: Text(state.error!),
              leading: const Icon(Icons.error_outline),
              actions: <Widget>[
                TextButton(
                  onPressed: () => ref.invalidate(
                    mobileCodexControllerProvider(widget.hostId, widget.tabId),
                  ),
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: controller.clearError,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ),
        if (state.queuedMessages.isNotEmpty)
          _MobileQueueBar(
            messages: state.queuedMessages,
            controller: controller,
          ),
        _MobileComposer(
          controller: _composer,
          focusNode: _composerFocus,
          state: state,
          attachments: _attachments,
          busy: state.busy,
          interrupting: state.interrupting,
          onAttach: () => _pickImage(controller),
          onRemoveAttachment: (attachment) =>
              setState(() => _attachments.remove(attachment)),
          onSend: () => _send(controller),
          onSteer: () => _steer(controller),
          onStop: controller.stop,
          canAttach: controller.supportsImageUpload,
          onModel: controller.setModel,
          onReasoning: controller.setReasoning,
          onSpeed: controller.setSpeed,
          onPermission: controller.setPermissionMode,
          onPlan: controller.setPlanMode,
          onCollaboration: controller.setCollaborationMode,
          onInsertToken: _insertToken,
          onCompact: controller.compact,
          onReview: () => _review(context, controller),
          onRename: () => _rename(context, controller, state.title),
        ),
      ],
    );
  }

  void _scheduleTimelinePin() {
    if (!_timeline.hasClients) return;
    final position = _timeline.position;
    final nearBottom =
        position.maxScrollExtent - position.pixels <= AleraTokens.space48;
    if (!nearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_timeline.hasClients) return;
      _timeline.jumpTo(_timeline.position.maxScrollExtent);
    });
  }

  Future<void> _send(MobileCodexController controller) async {
    final text = _composer.text;
    final attachments = List<Map<String, Object?>>.of(_attachments);
    _composer.clear();
    _attachments.clear();
    await controller.send(text, attachments: attachments);
  }

  Future<void> _steer(MobileCodexController controller) async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await controller.steer(text);
  }

  void _insertToken(String token) {
    final current = _composer.text.trimRight();
    _composer.text = current.isEmpty ? token : '$current $token';
    _composer.selection = TextSelection.collapsed(
      offset: _composer.text.length,
    );
  }

  Future<void> _pickImage(MobileCodexController controller) async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    String path;
    try {
      path = await controller.uploadImage(
        format: promptImageFormatForFileName(image.name),
        sizeBytes: await image.length(),
        openRead: () => image.openRead(),
      );
    } on Object {
      return;
    }
    if (!mounted) return;
    setState(() {
      _attachments.add(<String, Object?>{'type': 'localImage', 'path': path});
    });
  }

  Future<void> _rename(
    BuildContext context,
    MobileCodexController controller,
    String? current,
  ) async {
    final input = TextEditingController(text: current ?? 'Codex');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Codex Thread'),
        content: TextField(controller: input, autofocus: true),
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
    if (value != null && value.trim().isNotEmpty) {
      await controller.rename(value);
    }
  }

  Future<void> _review(
    BuildContext context,
    MobileCodexController controller,
  ) async {
    final input = TextEditingController();
    var target = 'uncommittedChanges';
    var delivery = 'inline';
    final selection = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Start Review'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: target,
                decoration: const InputDecoration(labelText: 'Target'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'uncommittedChanges',
                    child: Text('Uncommitted Changes'),
                  ),
                  DropdownMenuItem(
                    value: 'baseBranch',
                    child: Text('Base Branch'),
                  ),
                  DropdownMenuItem(value: 'commit', child: Text('Commit')),
                  DropdownMenuItem(value: 'custom', child: Text('Custom')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => target = value);
                },
              ),
              if (target != 'uncommittedChanges')
                TextField(
                  controller: input,
                  decoration: InputDecoration(
                    labelText: switch (target) {
                      'baseBranch' => 'Branch',
                      'commit' => 'Commit Sha',
                      _ => 'Instructions',
                    },
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: delivery,
                decoration: const InputDecoration(labelText: 'Delivery'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'inline', child: Text('Inline')),
                  DropdownMenuItem(value: 'detached', child: Text('Detached')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => delivery = value);
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(<String, String?>{
                'target': target,
                'argument': input.text,
                'delivery': delivery,
              }),
              child: const Text('Start Review'),
            ),
          ],
        ),
      ),
    );
    input.dispose();
    if (selection == null || !mounted) return;
    await controller.review(
      target: selection['target'] ?? 'uncommittedChanges',
      argument: selection['argument'],
      delivery: selection['delivery'],
    );
  }
}
