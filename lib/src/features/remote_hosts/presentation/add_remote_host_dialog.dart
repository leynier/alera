import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/presentation/add_remote_host_done_step.dart';
import 'package:alera/src/features/remote_hosts/presentation/add_remote_host_install_step.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_connection_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AddRemoteHostStep(final String label) {
  connection('Connection'),
  install('Install Runtime'),
  done('Done'),
}

/// What Add Host ends with: the host it registered, if it got that far, and
/// whether the user asked to add a project there next.
class const AddRemoteHostOutcome({
  required final String hostId,
  final bool addProject = false,
});

/// Guided Add Host: who the host is, installing the Alera runtime there, and
/// a summary. Closing it never cancels an install that is already running.
class const AddRemoteHostDialog({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AddRemoteHostDialog> createState() =>
      _AddRemoteHostDialogState();
}

class _AddRemoteHostDialogState extends ConsumerState<AddRemoteHostDialog> {
  final RemoteHostConnectionFormController _form =
      RemoteHostConnectionFormController();
  AddRemoteHostStep _step = AddRemoteHostStep.connection;
  String? _hostId;
  bool _saving = false;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  void _close({bool addProject = false}) {
    final hostId = _hostId;
    Navigator.of(context).pop(
      hostId == null
          ? null
          : AddRemoteHostOutcome(hostId: hostId, addProject: addProject),
    );
  }

  /// Saving is the test: `sshTarget.check` only probes a stored host, so the
  /// connection is registered here and checked on the next step.
  Future<void> _continue() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final controller = ref.read(remoteHostsControllerProvider.notifier);
    final hostId = _hostId;
    final result = hostId == null
        ? await controller.addHost(_form.values)
        : await controller.saveConnection(hostId, _form.values);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    final saved = result.target;
    if (!result.succeeded || saved == null) {
      _form.error = result.errorMessage;
      return;
    }
    setState(() {
      _hostId = saved.id;
      _step = AddRemoteHostStep.install;
    });
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(
      remoteHostsControllerProvider.select((state) => state.capabilities),
    );
    final hostId = _hostId;
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(title: 'Add Host', onClose: _close),
            const SizedBox(height: AleraTokens.space12),
            AleraHorizontalScrollView(
              child: Row(
                children: <Widget>[
                  for (final step in AddRemoteHostStep.values) ...<Widget>[
                    if (step != AddRemoteHostStep.connection)
                      const SizedBox(width: AleraTokens.space8),
                    AleraChip(label: step.label, leading: _stepIcon(step)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            Flexible(
              child: switch (_step) {
                AddRemoteHostStep.connection => _connectionStep(
                  capabilities.identityFile,
                ),
                AddRemoteHostStep.install => AddRemoteHostInstallStep(
                  hostId: hostId!,
                  onBack: () =>
                      setState(() => _step = AddRemoteHostStep.connection),
                  onClose: _close,
                  onFinished: () =>
                      setState(() => _step = AddRemoteHostStep.done),
                ),
                AddRemoteHostStep.done => AddRemoteHostDoneStep(
                  hostId: hostId!,
                  onAddProject: () => _close(addProject: true),
                  onDone: _close,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _stepIcon(AddRemoteHostStep step) {
    if (step.index < _step.index) {
      return AleraIcons.check;
    }
    return step == _step ? AleraIcons.radioOn : AleraIcons.circle;
  }

  Widget _connectionStep(bool identityFileSupported) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Flexible(
          child: SingleChildScrollView(
            child: RemoteHostConnectionForm(
              controller: _form,
              identityFileSupported: identityFileSupported,
              enabled: !_saving,
              autofocus: true,
              onSubmitted: (_) => unawaited(_continue()),
            ),
          ),
        ),
        const SizedBox(height: AleraTokens.space20),
        Row(
          mainAxisAlignment: .end,
          children: <Widget>[
            TextButton(onPressed: _close, child: const Text('Cancel')),
            const SizedBox(width: AleraTokens.space8),
            FilledButton(
              onPressed: _saving ? null : () => unawaited(_continue()),
              child: Text(_saving ? 'Saving…' : 'Continue'),
            ),
          ],
        ),
      ],
    );
  }
}
