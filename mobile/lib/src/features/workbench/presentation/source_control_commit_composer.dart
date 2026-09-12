import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_commit_draft.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_commands.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Commit message field plus the one-tap action: Commit once something is
/// staged and a message is typed, otherwise what the runtime suggests (sync,
/// publish, stage all...). The other commit variants sit behind a sheet.
class const SourceControlCommitComposer({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final MobileGitStatusSnapshot snapshot,
  required final bool busy,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SourceControlCommitComposer> createState() =>
      _SourceControlCommitComposerState();
}

class _SourceControlCommitComposerState
    extends ConsumerState<SourceControlCommitComposer> {
  late final TextEditingController _message;

  @override
  void initState() {
    super.initState();
    _message = TextEditingController(
      text: ref.read(
        sourceControlCommitDraftProvider(widget.hostId, widget.workspaceId),
      ),
    );
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  SourceControlCommandRunner get _runner => SourceControlCommandRunner(
    context: context,
    ref: ref,
    hostId: widget.hostId,
    workspaceId: widget.workspaceId,
  );

  @override
  Widget build(BuildContext context) {
    final draftProvider = sourceControlCommitDraftProvider(
      widget.hostId,
      widget.workspaceId,
    );
    final draft = ref.watch(draftProvider);
    ref.listen(draftProvider, (_, next) {
      // A successful commit clears the draft from outside the field.
      if (next != _message.text) {
        _message.text = next;
      }
    });
    final snapshot = widget.snapshot;
    final primary = SourceControlCommand.primary(snapshot, draft);
    final showMessage = snapshot.actions.commit || snapshot.entries.isNotEmpty;
    final hasCommitOptions = SourceControlCommand.commitOptions.any(
      (command) => command.isAvailable(snapshot, message: draft),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        0,
        AleraTokens.space16,
        AleraTokens.space8,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (showMessage) ...<Widget>[
            AleraTextField(
              controller: _message,
              hintText: 'Message',
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              enabled: !widget.busy,
              onChanged: ref.read(draftProvider.notifier).update,
            ),
            const SizedBox(height: AleraTokens.space8),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () => _runner.perform(primary, snapshot),
                  icon: Icon(primary.icon, size: 16),
                  label: Text(primary.label),
                ),
              ),
              if (hasCommitOptions) ...<Widget>[
                const SizedBox(width: AleraTokens.space8),
                AleraIconButton(
                  tooltip: 'Commit Options',
                  icon: AleraIcons.chevronDown,
                  onPressed: widget.busy
                      ? null
                      : () => showSourceControlCommandSheet(
                          _runner,
                          snapshot,
                          SourceControlCommand.commitOptions,
                          message: draft,
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
