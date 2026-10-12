import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/diagnostics/application/diagnostics_providers.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_usage_provider.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_advanced_group.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_connection_dialog.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_diagnostics_group.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_header_card.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_projects_group.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_runtime_update_flow.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_state_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String remoteHostInUseRemoveReason =
    "Remove the host's projects and workspaces first.";

/// Everything about one host: header, what its state asks for, its projects,
/// and the settings and diagnostics behind it.
class const RemoteHostDetail({
  super.key,
  required final RemoteHostView host,
  required final RemoteHostUsage usage,
  required final RemoteHostCapabilities capabilities,
  required final RemoteHostAdvancedDraft draft,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<RemoteHostDetail> createState() => _RemoteHostDetailState();
}

class _RemoteHostDetailState extends ConsumerState<RemoteHostDetail> {
  bool _checking = false;
  bool _savingAdvanced = false;

  RemoteHostView get _host => widget.host;

  RemoteHostsController get _controller =>
      ref.read(remoteHostsControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final host = _host;
    final installing = host.status is RemoteHostInstalling;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          RemoteHostHeaderCard(
            host: host,
            usage: widget.usage,
            capabilities: widget.capabilities,
            checking: _checking,
            onPrimaryAction: (action) => unawaited(_runPrimary(action)),
            onCheckConnection: widget.capabilities.hostStatus
                ? () => unawaited(_checkConnection())
                : null,
            onEditConnection: () =>
                unawaited(showRemoteHostConnectionDialog(context, host)),
            onCopySshCommand: () => unawaited(_copySshCommand()),
            onRemove: () => unawaited(_remove()),
            removeBlockedReason: widget.usage.isEmpty
                ? null
                : remoteHostInUseRemoveReason,
          ),
          RemoteHostStateStrip(
            key: ValueKey<String>('state-strip-${host.id}'),
            host: host,
            capabilities: widget.capabilities,
            onInstall: () => unawaited(_controller.install(host.id)),
            onCancelInstall: () =>
                unawaited(_controller.cancelInstall(host.id)),
            onRetry: () => unawaited(_retry()),
            onCopyError: (text) => unawaited(_copyError(text)),
            onUpdateRuntime: () => unawaited(_updateRuntime()),
            onDismissError: () => _controller.clearError(host.id),
          ),
          const SizedBox(height: AleraTokens.space24),
          RemoteHostProjectsGroup(host: host),
          const SizedBox(height: AleraTokens.space24),
          RemoteHostAdvancedGroup(
            draft: widget.draft,
            locked: installing,
            saving: _savingAdvanced,
            identityFileSupported: widget.capabilities.identityFile,
            onSave: () => unawaited(_saveAdvanced()),
          ),
          const SizedBox(height: AleraTokens.space24),
          RemoteHostDiagnosticsGroup(
            target: host.target,
            onCopyError: (text) => unawaited(_copyError(text)),
            onOpenLogs: () => unawaited(_openLogs()),
          ),
        ],
      ),
    );
  }

  Future<void> _runPrimary(RemoteHostPrimaryAction action) async {
    final id = _host.id;
    switch (action) {
      case RemoteHostPrimaryAction.install:
        _controller.dismissInstallFailure(id);
        await _controller.install(id);
      case RemoteHostPrimaryAction.connect:
        await _controller.connect(id);
      case RemoteHostPrimaryAction.disconnect:
        await _controller.disconnect(id);
      case RemoteHostPrimaryAction.update:
        await _updateRuntime();
      case RemoteHostPrimaryAction.installing ||
          RemoteHostPrimaryAction.connecting:
        break;
    }
  }

  Future<void> _retry() async {
    final status = _host.status;
    if (status is RemoteHostError &&
        status.origin == RemoteHostErrorOrigin.install) {
      return _runPrimary(RemoteHostPrimaryAction.install);
    }
    return _runPrimary(RemoteHostPrimaryAction.connect);
  }

  Future<void> _updateRuntime() async {
    await updateRemoteHostRuntime(context, ref, _host.id);
  }

  Future<void> _checkConnection() async {
    setState(() => _checking = true);
    await _controller.checkConnection(_host.id);
    if (mounted) {
      setState(() => _checking = false);
    }
  }

  Future<void> _saveAdvanced() async {
    final draft = widget.draft;
    setState(() => _savingAdvanced = true);
    final result = await _controller.saveAdvanced(_host.id, draft.values);
    if (!mounted) {
      return;
    }
    setState(() => _savingAdvanced = false);
    if (result.target case final saved?) {
      draft.syncFrom(saved);
    }
  }

  Future<void> _copySshCommand() async {
    final result = await _controller.copySshCommand(_host.id);
    if (result.succeeded) {
      AleraToast.publish(message: 'SSH command copied', tone: .success);
    }
  }

  Future<void> _copyError(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    AleraToast.publish(message: 'Error copied', tone: .success);
  }

  Future<void> _openLogs() async {
    final opened = await ref
        .read(diagnosticsServiceProvider)
        .revealAppLogDirectory();
    if (!opened) {
      AleraToast.publish(
        message: 'Could not open the logs folder.',
        tone: .error,
      );
    }
  }

  Future<void> _remove() async {
    final host = _host;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Remove ${host.alias}?',
        message: 'Alera forgets this host. The Alera runtime and your files on the host are not deleted.',
        confirmLabel: 'Remove',
        destructive: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    final result = await _controller.removeHost(host.id);
    if (result.succeeded) {
      AleraToast.publish(message: '${host.alias} removed', tone: .success);
    }
  }
}
