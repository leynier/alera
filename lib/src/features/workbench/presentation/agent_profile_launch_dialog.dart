import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_field_overlay.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_submission.dart';
import 'package:alera/src/features/workbench/domain/terminal_image_paste.dart';
import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_attachment_bar.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

Future<List<String>> pickAgentProfileLaunchFiles() async {
  final files = await openFiles();
  return <String>[
    for (final file in files)
      if (file.path.isNotEmpty) file.path,
  ];
}

Future<void> showAgentProfileLaunchDialog(
  BuildContext context, {
  required AgentProfile profile,
  required String workspacePath,
  required Future<void> Function({required String prompt}) onLaunch,
  TerminalClipboard clipboard = const NativeTerminalClipboard(),
  Future<List<String>> Function() pickFiles = pickAgentProfileLaunchFiles,
  ExternalUriLauncher? externalUriLauncher,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AgentProfileLaunchDialog(
      profile: profile,
      workspacePath: workspacePath,
      onLaunch: onLaunch,
      clipboard: clipboard,
      pickFiles: pickFiles,
      externalUriLauncher: externalUriLauncher,
    ),
  );
}

class const AgentProfileLaunchDialog({
  super.key,
  required final AgentProfile profile,
  required final String workspacePath,
  required final Future<void> Function({required String prompt}) onLaunch,
  final TerminalClipboard clipboard = const NativeTerminalClipboard(),
  final Future<List<String>> Function()? pickFiles,
  final ExternalUriLauncher? externalUriLauncher,
}) extends StatefulWidget {
  @override
  State<AgentProfileLaunchDialog> createState() =>
      _AgentProfileLaunchDialogState();
}

class _AgentProfileLaunchDialogState extends State<AgentProfileLaunchDialog> {
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();
  final List<TerminalComposerAttachment> _attachments =
      <TerminalComposerAttachment>[];
  int _nextAttachmentId = 0;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _promptController.dispose();
    _promptFocusNode.dispose();
    super.dispose();
  }

  void _update(VoidCallback update) => setState(update);

  bool get _canStart {
    return !_working &&
        (_promptController.text.trim().isNotEmpty || _attachments.isNotEmpty);
  }

  Future<void> _submit({required bool skip}) async {
    if (_working) {
      return;
    }
    final prompt = skip
        ? ''
        : buildTerminalComposerSubmission(
            prompt: _promptController.text,
            attachments: _attachments,
            workspacePath: widget.workspacePath,
          );
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
    } on Object catch (error) {
      if (mounted) {
        _update(() {
          _working = false;
          _error = userFacingExceptionMessage(error);
        });
      }
    }
  }

  Future<void> _addFiles() async {
    try {
      final paths = await (widget.pickFiles ?? pickAgentProfileLaunchFiles)();
      if (!mounted || paths.isEmpty) {
        return;
      }
      _addPaths(paths);
    } on Object catch (error) {
      if (mounted) {
        _update(() => _error = userFacingExceptionMessage(error));
      }
    }
  }

  void _addPaths(Iterable<String> paths) {
    var changed = false;
    for (final path in paths) {
      if (path.isEmpty) {
        continue;
      }
      final kind = terminalComposerAttachmentKindForPath(path);
      final displayName = sanitizeTerminalImagePastePath(p.basename(path));
      _attachments.add(
        TerminalComposerAttachment(
          id: 'attachment-${_nextAttachmentId++}',
          kind: kind,
          path: path,
          displayName: displayName.isEmpty
              ? kind == TerminalComposerAttachmentKind.image
                    ? 'Pasted Image'
                    : 'Pasted File'
              : displayName,
        ),
      );
      changed = true;
    }
    if (changed) {
      _update(() => _error = null);
    }
  }

  Future<bool> _pasteClipboard() async {
    try {
      final filePaths = await widget.clipboard.readFilePaths();
      if (filePaths.isNotEmpty) {
        _addPaths(filePaths);
        return true;
      }
    } catch (_) {
      // Fall through to text and image clipboard formats.
    }
    String? clipboardText;
    try {
      clipboardText = await widget.clipboard.readText();
    } catch (_) {
      // Image-only clipboards can reject text reads on some platforms.
    }
    if (clipboardText != null && clipboardText.isNotEmpty) {
      return false;
    }
    try {
      final imagePath = await widget.clipboard.saveImageAsTempFile();
      if (!mounted || imagePath == null || imagePath.isEmpty) {
        return false;
      }
      _addPaths(<String>[imagePath]);
      return true;
    } catch (_) {
      if (mounted) {
        _update(() => _error = 'Could not paste clipboard image.');
      }
      return true;
    }
  }

  Future<void> _openFile(String path) async {
    try {
      await (widget.externalUriLauncher ?? UrlLauncherExternalUriLauncher())
          .open(.file(path));
    } on Object catch (error) {
      if (mounted) {
        _update(() => _error = 'Could not open attached file: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 620,
      maxHeight: 720,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
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
                  onPressed: _working
                      ? null
                      : () => Navigator.of(context).pop(),
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
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    AiDictationFieldOverlay(
                      controller: _promptController,
                      focusNode: _promptFocusNode,
                      initialPrompt:
                          'The user is describing a software task for Alera.',
                      controlKey: const ValueKey<String>(
                        'agent-profile-launch-dictation-control',
                      ),
                      enabled: !_working,
                      child: AleraTextField(
                        controller: _promptController,
                        focusNode: _promptFocusNode,
                        labelText: 'Initial Prompt',
                        hintText: 'Describe what the agent should do or paste an image',
                        minLines: 4,
                        maxLines: 8,
                        autofocus: true,
                        enabled: !_working,
                        onChanged: (_) {
                          if (_error != null || !_working) {
                            setState(() {});
                          }
                        },
                        onPaste: _pasteClipboard,
                        suffix: const SizedBox(width: AleraTokens.space32),
                      ),
                    ),
                    TerminalComposerAttachmentBar(
                      attachments: _attachments,
                      onRemove: (id) {
                        _update(
                          () => _attachments.removeWhere(
                            (attachment) => attachment.id == id,
                          ),
                        );
                      },
                      onOpenFile: (path) => unawaited(_openFile(path)),
                      enabled: !_working,
                    ),
                    const SizedBox(height: AleraTokens.space12),
                    OutlinedButton.icon(
                      onPressed: _working ? null : () => unawaited(_addFiles()),
                      icon: const Icon(AleraIcons.attach, size: 16),
                      label: const Text('Add Files'),
                    ),
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
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: AleraTokens.space8),
                          const Expanded(child: Text('Starting agent')),
                        ] else ...<Widget>[
                          const Spacer(),
                          TextButton(
                            onPressed: () => unawaited(_submit(skip: true)),
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
          ],
        ),
      ),
    );
  }
}
