import 'dart:async';

import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_choice_dialog.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_usage_provider.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_advanced_group.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_detail.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_list_row.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String remoteHostsEmptyMessage =
    'Run workspaces on another machine over SSH. Alera installs its runtime there for you.';

enum _LeaveChoice { save, discard }

/// Settings > Remote Hosts: every host on the left, the selected one on the
/// right. [initialHostId] opens on that host; without it, the first one.
class const RemoteHostsSettingsPane({super.key, final String? initialHostId})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<RemoteHostsSettingsPane> createState() =>
      _RemoteHostsSettingsPaneState();
}

class _RemoteHostsSettingsPaneState
    extends ConsumerState<RemoteHostsSettingsPane> {
  late String? _selectedHostId = widget.initialHostId;
  RemoteHostAdvancedDraft? _draft;

  @override
  void dispose() {
    _draft?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(remoteHostsControllerProvider);
    ref.listen(remoteHostsControllerProvider, (_, next) {
      final draft = _draft;
      if (next.hostById(draft?.hostId) case final host?) {
        draft!.syncFrom(host.target);
      }
    });
    final usage = ref.watch(remoteHostUsageProvider);
    if (state.hosts.isEmpty) {
      if (state.loading) {
        return const AleraEmptyState(
          loading: true,
          message: 'Loading remote hosts…',
        );
      }
      if (state.loadError case final error?) {
        return AleraEmptyState(
          icon: AleraIcons.error,
          title: 'Remote hosts unavailable',
          message: error,
        );
      }
      return AleraEmptyState(
        icon: AleraIcons.host,
        title: 'No remote hosts',
        message: remoteHostsEmptyMessage,
        action: FilledButton(
          onPressed: () => unawaited(_addHost()),
          child: const Text('Add Host'),
        ),
      );
    }
    final selected = state.hostById(_selectedHostId) ?? state.hosts.first;
    final draft = _draftFor(selected);
    return ListenableBuilder(
      listenable: draft,
      builder: (context, child) => PopScope(
        canPop: !draft.isDirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            unawaited(_closeAfterLeaving());
          }
        },
        child: child!,
      ),
      child: AleraMasterDetail(
        masterTitle: 'Remote Hosts',
        masterAction: AleraIconButton(
          tooltip: 'Add Host',
          icon: AleraIcons.add,
          onPressed: () => unawaited(_addHost()),
        ),
        master: SingleChildScrollView(
          child: AleraPanel(
            clipBehavior: .antiAlias,
            children: <Widget>[
              for (final host in state.hosts)
                RemoteHostListRow(
                  host: host,
                  usage: usage[host.id] ?? const RemoteHostUsage(),
                  selected: host.id == selected.id,
                  onTap: () => unawaited(_select(host.id)),
                ),
            ],
          ),
        ),
        detail: RemoteHostDetail(
          key: ValueKey<String>('remote-host-detail-${selected.id}'),
          host: selected,
          usage: usage[selected.id] ?? const RemoteHostUsage(),
          capabilities: state.capabilities,
          draft: draft,
        ),
      ),
    );
  }

  RemoteHostAdvancedDraft _draftFor(RemoteHostView host) {
    final current = _draft;
    if (current != null && current.hostId == host.id) {
      return current;
    }
    if (current != null) {
      // The previous detail still listens until this frame unmounts it.
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return _draft = RemoteHostAdvancedDraft(host.target);
  }

  Future<void> _select(String hostId) async {
    if (hostId == _draft?.hostId) {
      return;
    }
    if (!await _leaveDraft()) {
      return;
    }
    if (mounted) {
      setState(() => _selectedHostId = hostId);
    }
  }

  Future<void> _addHost() async {
    if (!await _leaveDraft() || !mounted) {
      return;
    }
    final hostId = await showAddRemoteHostFlow(context, ref);
    if (hostId != null && mounted) {
      setState(() => _selectedHostId = hostId);
    }
  }

  Future<void> _closeAfterLeaving() async {
    if (await _leaveDraft() && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Whether the user may leave the selected host: true when nothing is
  /// unsaved, or once they saved or discarded it.
  Future<bool> _leaveDraft() async {
    final draft = _draft;
    if (draft == null || !draft.isDirty) {
      return true;
    }
    final host = ref.read(remoteHostsControllerProvider).hostById(draft.hostId);
    if (host == null) {
      return true;
    }
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (_) => AleraChoiceDialog<_LeaveChoice>(
        title: 'Save Changes?',
        message: '${host.alias} has unsaved advanced settings.',
        primaryLabel: 'Save',
        primaryValue: _LeaveChoice.save,
        secondaryLabel: 'Discard',
        secondaryValue: _LeaveChoice.discard,
        destructiveSecondary: true,
        cancelLabel: 'Keep Editing',
      ),
    );
    switch (choice) {
      case _LeaveChoice.save:
        final result = await ref
            .read(remoteHostsControllerProvider.notifier)
            .saveAdvanced(draft.hostId, draft.values);
        if (result.target case final saved?) {
          draft.syncFrom(saved);
        }
        return result.succeeded;
      case _LeaveChoice.discard:
        draft.revert();
        return true;
      case null:
        return false;
    }
  }
}
