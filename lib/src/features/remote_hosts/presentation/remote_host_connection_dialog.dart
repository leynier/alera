import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_form_values.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_connection_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showRemoteHostConnectionDialog(
  BuildContext context,
  RemoteHostView host,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => RemoteHostConnectionDialog(host: host),
  );
}

/// Edits a host's identity: alias, SSH Address and authentication. Changing
/// how the host is reached drops its link, so this lives in a modal rather
/// than inline.
class const RemoteHostConnectionDialog({
  super.key,
  required final RemoteHostView host,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<RemoteHostConnectionDialog> createState() =>
      _RemoteHostConnectionDialogState();
}

class _RemoteHostConnectionDialogState
    extends ConsumerState<RemoteHostConnectionDialog> {
  late final RemoteHostConnectionFormController _form =
      RemoteHostConnectionFormController(
        initial: RemoteHostConnectionValues.fromTarget(widget.host.target),
      );
  bool _saving = false;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final result = await ref
        .read(remoteHostsControllerProvider.notifier)
        .saveConnection(widget.host.id, _form.values);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (result.succeeded) {
      Navigator.of(context).pop();
    } else {
      _form.error = result.errorMessage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(
      remoteHostsControllerProvider.select((state) => state.capabilities),
    );
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Edit Connection',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space16),
            Flexible(
              child: SingleChildScrollView(
                child: RemoteHostConnectionForm(
                  controller: _form,
                  identityFileSupported: capabilities.identityFile,
                  enabled: !_saving,
                  onSubmitted: (_) => unawaited(_save()),
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: .end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _saving ? null : () => unawaited(_save()),
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
