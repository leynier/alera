import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_control.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_review_bar.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_attachment_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_image_picker.dart';
import 'package:alera_mobile/src/features/workbench/presentation/prompt_attachment_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/prompt_path_insertion.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

part 'agent_profile_launch_attachments.dart';

/// Collects a starting prompt for an opted-in Agent Profile, matching desktop
/// New Tab launch: a non-empty prompt, or Skip to open the agent empty.
Future<void> showAgentProfileLaunchSheet(
  BuildContext context, {
  required AgentProfileSummary profile,
  required String hostId,
  required String workspaceId,
  required Future<void> Function({required String prompt}) onLaunch,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AgentProfileLaunchSheet(
        profile: profile,
        hostId: hostId,
        workspaceId: workspaceId,
        onLaunch: onLaunch,
      ),
    ),
  );
}

class const AgentProfileLaunchSheet({
  super.key,
  required final AgentProfileSummary profile,
  required final String hostId,
  required final String workspaceId,
  required final Future<void> Function({required String prompt}) onLaunch,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentProfileLaunchSheet> createState() =>
      _AgentProfileLaunchSheetState();
}

final Logger _agentProfileLaunchLogger = Logger('AgentProfileLaunchSheet');

class _AgentProfileLaunchSheetState
    extends ConsumerState<AgentProfileLaunchSheet> {
  final TextEditingController _promptController = TextEditingController();
  bool _working = false;
  bool _attaching = false;
  bool _hasPrompt = false;
  String? _error;

  String get _dictationTarget =>
      'agent-profile-launch-${widget.hostId}-${widget.profile.id}';

  bool get _busy => _working || _attaching;

  bool get _canStart => !_busy && _hasPrompt;

  @override
  void initState() {
    super.initState();
    _promptController.addListener(_onPromptChanged);
  }

  @override
  void dispose() {
    _promptController.removeListener(_onPromptChanged);
    _promptController.dispose();
    super.dispose();
  }

  void _onPromptChanged() {
    final hasPrompt = _promptController.text.trim().isNotEmpty;
    if (!mounted || (hasPrompt == _hasPrompt && _error == null)) {
      return;
    }
    setState(() {
      _hasPrompt = hasPrompt;
    });
  }

  void _update(VoidCallback update) => setState(update);

  Future<void> _submit({required bool skip}) async {
    if (_busy) {
      return;
    }
    final prompt = skip ? '' : _promptController.text;
    if (!skip && prompt.trim().isEmpty) {
      _update(
        () =>
            _error = 'Write a prompt, attach files, or skip to open the agent.',
      );
      return;
    }
    _update(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.onLaunch(prompt: prompt);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object catch (error, stackTrace) {
      _agentProfileLaunchLogger.warning(
        'could not start agent profile',
        error,
        stackTrace,
      );
      if (mounted) {
        _update(() {
          _working = false;
          _error = _launchErrorMessage(error);
        });
      }
    }
  }

  void _submitFromKeyboard() {
    if (_canStart) {
      unawaited(_submit(skip: false));
    }
  }

  String _launchErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'Could not start the agent. Try again.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.watch(workspaceClientProvider(widget.hostId));
    final dictationEnabled =
        ref.watch(mobileAiDictationSettingsControllerProvider).value?.enabled ==
        true;
    final promptEnabled = !_busy;
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(AleraIcons.agent, color: AleraTokens.accent),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      'Start ${widget.profile.name}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: .bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(AleraIcons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: AleraTokens.space12),
              Text(
                'Write a starting prompt, attach files, or skip to open this agent without one.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              const SizedBox(height: AleraTokens.space16),
              if (dictationEnabled)
                MobileAiDictationReviewBar(
                  hostId: widget.hostId,
                  targetKey: _dictationTarget,
                ),
              Stack(
                children: <Widget>[
                  CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(
                        .enter,
                        control: true,
                        includeRepeats: false,
                      ): _submitFromKeyboard,
                      const SingleActivator(
                        .enter,
                        meta: true,
                        includeRepeats: false,
                      ): _submitFromKeyboard,
                    },
                    child: AleraTextField(
                      controller: _promptController,
                      labelText: 'Initial Prompt',
                      hintText: 'Describe what the agent should do',
                      minLines: 4,
                      maxLines: 8,
                      autofocus: true,
                      enabled: promptEnabled,
                      keyboardType: TextInputType.multiline,
                      suffix: dictationEnabled
                          ? const SizedBox(width: AleraTokens.minTapTarget)
                          : null,
                    ),
                  ),
                  if (dictationEnabled)
                    Positioned(
                      right: AleraTokens.space4,
                      bottom: AleraTokens.space4,
                      child: MobileAiDictationControl(
                        key: const ValueKey<String>(
                          'agent-profile-launch-dictation-control',
                        ),
                        hostId: widget.hostId,
                        targetKey: _dictationTarget,
                        workspaceId: widget.workspaceId,
                        controller: _promptController,
                        enabled: promptEnabled,
                      ),
                    ),
                ],
              ),
              if (_canAttach) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => unawaited(_showAttachmentPicker()),
                  icon: const Icon(AleraIcons.attach, size: 16),
                  label: const Text('Add Attachment'),
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: AleraTokens.space16),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.error,
                  ),
                ),
              ],
              const SizedBox(height: AleraTokens.space20),
              Row(
                children: <Widget>[
                  if (_working) ...<Widget>[
                    const SizedBox.square(
                      dimension: AleraTokens.spaceLg,
                      child: CircularProgressIndicator(
                        strokeWidth: AleraTokens.strokeSm,
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    const Expanded(child: Text('Starting agent')),
                  ] else ...<Widget>[
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => unawaited(_submit(skip: true)),
                      child: const Text('Skip'),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    FilledButton.icon(
                      onPressed: _canStart
                          ? () => unawaited(_submit(skip: false))
                          : null,
                      icon: const Icon(AleraIcons.agent, size: 16),
                      label: const Text('Start Agent'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
