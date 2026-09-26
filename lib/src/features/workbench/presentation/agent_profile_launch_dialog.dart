import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_adapters.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_session_id.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
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
import 'package:uuid/uuid.dart';

part 'agent_profile_launch_dialog_content.dart';

typedef AgentProfileLaunchCallback = Future<void> Function({
  required String prompt,
  String? resumeSessionId,
  String? clientMutationId,
});

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
  required AgentProfileLaunchCallback onLaunch,
  Future<bool> Function()? supportsResume,
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
      supportsResume: supportsResume,
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
  required final AgentProfileLaunchCallback onLaunch,
  final Future<bool> Function()? supportsResume,
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
  final _sessionController = TextEditingController();
  final _sessionFocusNode = FocusNode();
  bool _resume = false;
  bool _supportsResume = false;
  String? _mutationId;
  String? _mutationSessionId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadResumeSupport());
  }

  Future<void> _loadResumeSupport() async {
    try {
      final supported =
          agentProfileAdapterFromKey(widget.profile.agentType) != null &&
          await (widget.supportsResume?.call() ?? Future.value(false));
      if (mounted) setState(() => _supportsResume = supported);
    } on Object {
      // A failed capability check must not turn resume into a fresh launch.
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _promptFocusNode.dispose();
    _sessionController.dispose();
    _sessionFocusNode.dispose();
    super.dispose();
  }

  void _update(VoidCallback update) => setState(update);

  bool get _canStart {
    return !_working &&
        (_resume
            ? _supportsResume && isUsableAgentSessionId(_sessionController.text)
            : _promptController.text.trim().isNotEmpty ||
                  _attachments.isNotEmpty);
  }

  Future<void> _submit({required bool skip}) async {
    if (_working) {
      return;
    }
    if (_resume && !_canStart) return;
    final sessionId = _resume ? _sessionController.text.trim() : null;
    if (sessionId != null &&
        (_mutationId == null || _mutationSessionId != sessionId)) {
      _mutationId = const Uuid().v4();
      _mutationSessionId = sessionId;
    }
    final prompt = skip || _resume
        ? ''
        : buildTerminalComposerSubmission(
            prompt: _promptController.text,
            attachments: _attachments,
            workspacePath: widget.workspacePath,
          );
    if (!skip && !_resume && prompt.trim().isEmpty) {
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
      await widget.onLaunch(
        prompt: prompt,
        resumeSessionId: sessionId,
        clientMutationId: _resume ? _mutationId : null,
      );
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
  Widget build(BuildContext context) => _buildDialog(context);
}
