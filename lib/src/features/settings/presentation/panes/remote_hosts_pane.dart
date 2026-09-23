import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/host_link.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_editor.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_editor_controllers.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_field_normalizers.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_list_row.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_target_signatures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const RemoteHostSettingsPane({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<RemoteHostSettingsPane> createState() =>
      _RemoteHostSettingsPaneState();
}

class _RemoteHostSettingsPaneState
    extends ConsumerState<RemoteHostSettingsPane> {
  final RemoteHostEditorControllers _fields = RemoteHostEditorControllers();
  String? _selectedTargetId;
  bool _creatingNew = false;
  String _platform = '';
  String _arch = '';
  SshAuthKind _authKind = .agent;
  String? _error;
  SshTargetBootstrapPlan? _plan;
  SshTargetBootstrapProgress? _progress;
  bool _saving = false;
  bool _planning = false;
  bool _bootstrapping = false;
  bool _linkBusy = false;
  String? _seededEditorSignature;
  String? _seededStatusSignature;

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sshTargetBootstrapProgressProvider, (_, next) {
      final progress = next.asData?.value;
      if (progress == null || progress.targetId != _selectedTargetId) {
        return;
      }
      setState(() {
        _progress = progress;
        _bootstrapping = progress.status.isBusy;
        if (progress.error != null) {
          _error = progress.error;
        }
      });
    });

    final targetsAsync = ref.watch(sshTargetsProvider);
    final linkStates = hostLinkStatesById(
      ref.watch(hostLinksProvider).value ?? const <HostLinkState>[],
    );
    return targetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => RemoteHostError(message: error.toString()),
      data: (targets) {
        var selected = _selectedTarget(targets);
        if (selected != null) {
          _seedFromTarget(selected);
        } else if (!_creatingNew) {
          if (targets.isNotEmpty) {
            selected = targets.first;
            _selectedTargetId = selected.id;
            _seedFromTarget(selected);
          } else if (_selectedTargetId != null) {
            _clearEditor();
          }
        }
        final selectedTarget = selected;
        return AleraMasterDetail(
          masterTitle: 'SSH Targets',
          masterAction: AleraIconButton(
            tooltip: 'New Host',
            icon: AleraIcons.add,
            onPressed: _newTarget,
          ),
          master: targets.isEmpty
              ? const AleraEmptyState(
                  icon: AleraIcons.host,
                  title: 'No remote hosts',
                  message: 'Add an SSH target to install the runtime sidecar. Bootstrap does not create remote workspaces.',
                )
              : SingleChildScrollView(
                  child: AleraPanel(
                    clipBehavior: .antiAlias,
                    children: <Widget>[
                      for (final target in targets)
                        RemoteHostListRow(
                          target: target,
                          selected: target.id == _selectedTargetId,
                          onTap: () => _selectTarget(target),
                        ),
                    ],
                  ),
                ),
          detail: RemoteHostEditor(
            aliasController: _fields.alias,
            hostController: _fields.host,
            portController: _fields.port,
            usernameController: _fields.username,
            installDirController: _fields.installDir,
            projectsDirController: _fields.projectsDir,
            platform: _platform,
            arch: _arch,
            authKind: _authKind,
            error: _error,
            plan: _plan,
            progress: _progress,
            hasSelection: _selectedTargetId != null,
            saving: _saving,
            planning: _planning,
            bootstrapping: _bootstrapping,
            onPlatformChanged: (value) => setState(() => _platform = value),
            onArchChanged: (value) => setState(() => _arch = value),
            onAuthKindChanged: (value) => setState(() => _authKind = value),
            onSave: _saveTarget,
            onRemove: selectedTarget == null
                ? null
                : () => _removeTarget(selectedTarget),
            onPlan: selectedTarget == null ? null : _loadPlan,
            onBootstrap: selectedTarget == null ? null : _startBootstrap,
            onCancel: selectedTarget == null ? null : _cancelBootstrap,
            showLink:
                selectedTarget != null &&
                selectedTarget.bootstrapStatus == SshBootstrapStatus.installed,
            link: selectedTarget == null ? null : linkStates[selectedTarget.id],
            linkBusy: _linkBusy,
            onConnectLink: selectedTarget == null
                ? null
                : () => _connectLink(selectedTarget),
            onDisconnectLink: selectedTarget == null
                ? null
                : () => _disconnectLink(selectedTarget),
          ),
        );
      },
    );
  }

  Future<void> _connectLink(SshTarget target) => _runLinkOperation(
    () => ref.read(sshTargetRepositoryProvider).connectHostLink(target.id),
  );

  Future<void> _disconnectLink(SshTarget target) => _runLinkOperation(
    () => ref.read(sshTargetRepositoryProvider).disconnectHostLink(target.id),
  );

  Future<void> _runLinkOperation(
    Future<HostLinkState> Function() operation,
  ) async {
    setState(() {
      _linkBusy = true;
      _error = null;
    });
    try {
      await operation();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _linkBusy = false);
      }
    }
  }

  SshTarget? _selectedTarget(List<SshTarget> targets) {
    final selectedId = _selectedTargetId;
    return targets.where((target) => target.id == selectedId).firstOrNull;
  }

  void _seedFromTarget(SshTarget target) {
    final editorSignature = remoteHostEditorSignature(target);
    if (_seededEditorSignature != editorSignature) {
      _fields.seed(target);
      _platform = normalizedRemoteHostPlatform(target.platform);
      _arch = normalizedRemoteHostArch(target.arch);
      _authKind = target.authKind;
      _planning = false;
      _plan = null;
      _error = null;
      _seededEditorSignature = editorSignature;
    }

    final statusSignature = remoteHostStatusSignature(target);
    if (_seededStatusSignature == statusSignature) {
      return;
    }
    _bootstrapping = target.bootstrapStatus.isBusy;
    _progress = target.bootstrapStatus == SshBootstrapStatus.notInstalled
        ? null
        : SshTargetBootstrapProgress(
            jobId: '',
            targetId: target.id,
            status: target.bootstrapStatus,
            stage: target.bootstrapStatus.name,
            message: statusLabel(target.bootstrapStatus),
            error: target.lastError,
          );
    _seededStatusSignature = statusSignature;
  }

  void _selectTarget(SshTarget target) {
    setState(() {
      _creatingNew = false;
      _selectedTargetId = target.id;
      _seedFromTarget(target);
    });
  }

  void _newTarget() {
    setState(() {
      _clearEditor();
    });
  }

  void _clearEditor() {
    _selectedTargetId = null;
    _creatingNew = true;
    _fields.clear();
    _platform = '';
    _arch = '';
    _authKind = SshAuthKind.agent;
    _plan = null;
    _progress = null;
    _planning = false;
    _bootstrapping = false;
    _error = null;
    _seededEditorSignature = null;
    _seededStatusSignature = null;
  }

  Future<void> _saveTarget() async {
    if (_targetMutationLocked()) {
      return;
    }
    await _persistEditorTarget(showSaving: true);
  }

  Future<SshTarget?> _persistEditorTarget({required bool showSaving}) async {
    final alias = _fields.alias.text.trim();
    final host = _fields.host.text.trim();
    final username = _fields.username.text.trim();
    final port = _validatedPort();
    if (port == null) {
      return null;
    }
    if (alias.isEmpty || host.isEmpty || username.isEmpty) {
      setState(() => _error = 'Alias, host, and username are required');
      return null;
    }
    if (showSaving) {
      setState(() {
        _saving = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final now = DateTime.now().toUtc();
      final target = SshTarget(
        id: _selectedTargetId ?? 'ssh-${now.microsecondsSinceEpoch}',
        alias: alias,
        host: host,
        port: port,
        username: username,
        platform: emptyToNull(_platform),
        arch: emptyToNull(_arch),
        authKind: _authKind,
        createdAt: now,
        updatedAt: now,
        installDir: emptyToNull(_fields.installDir.text),
        projectsDir: emptyToNull(_fields.projectsDir.text),
      );
      final saved = await ref.read(sshTargetRepositoryProvider).upsert(target);
      if (!mounted) {
        return null;
      }
      setState(() {
        _selectedTargetId = saved.id;
        _creatingNew = false;
        if (showSaving) {
          _saving = false;
        }
        _seedFromTarget(saved);
      });
      return saved;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        if (showSaving) {
          _saving = false;
        }
        _error = error.toString();
      });
      return null;
    }
  }

  int? _validatedPort() {
    final port = parseRemoteHostPort(_fields.port.text);
    if (port == null) {
      setState(() => _error = 'Port must be between 1 and 65535');
    }
    return port;
  }

  bool _targetMutationLocked() {
    if (!_bootstrapping) {
      return false;
    }
    setState(() {
      _error = 'Cancel or wait for bootstrap before changing this host';
    });
    return true;
  }

  Future<void> _removeTarget(SshTarget target) async {
    if (_targetMutationLocked()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(sshTargetRepositoryProvider).remove(target.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _clearEditor();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadPlan() async {
    final requestedTargetId = _selectedTargetId;
    if (requestedTargetId == null) {
      return;
    }
    if (_targetMutationLocked()) {
      return;
    }
    setState(() {
      _planning = true;
      _error = null;
    });
    try {
      final saved = await _persistEditorTarget(showSaving: false);
      if (saved == null) {
        if (mounted && _selectedTargetId == requestedTargetId) {
          setState(() => _planning = false);
        }
        return;
      }
      final plan = await ref
          .read(sshTargetRepositoryProvider)
          .bootstrapPlan(
            targetId: saved.id,
            installDir: emptyToNull(_fields.installDir.text),
            platform: emptyToNull(_platform),
            arch: emptyToNull(_arch),
          );
      if (!mounted || _selectedTargetId != requestedTargetId) {
        return;
      }
      setState(() {
        _planning = false;
        _plan = plan;
      });
    } catch (error) {
      if (!mounted || _selectedTargetId != requestedTargetId) {
        return;
      }
      setState(() {
        _planning = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _startBootstrap() async {
    final requestedTargetId = _selectedTargetId;
    if (requestedTargetId == null) {
      return;
    }
    if (_targetMutationLocked()) {
      return;
    }
    setState(() {
      _bootstrapping = true;
      _error = null;
    });
    try {
      final saved = await _persistEditorTarget(showSaving: false);
      if (saved == null) {
        if (mounted) {
          setState(() => _bootstrapping = false);
        }
        return;
      }
      final job = await ref
          .read(sshTargetRepositoryProvider)
          .startBootstrap(
            targetId: saved.id,
            installDir: emptyToNull(_fields.installDir.text),
            platform: emptyToNull(_platform),
            arch: emptyToNull(_arch),
          );
      if (!mounted || _selectedTargetId != requestedTargetId) {
        return;
      }
      setState(() {
        _bootstrapping = job.status.isBusy;
        _progress = SshTargetBootstrapProgress(
          jobId: job.jobId,
          targetId: job.targetId,
          status: job.status,
          stage: 'installing',
          message: 'Remote runtime install started',
        );
      });
    } catch (error) {
      if (!mounted || _selectedTargetId != requestedTargetId) {
        return;
      }
      setState(() {
        _bootstrapping = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _cancelBootstrap() async {
    final targetId = _selectedTargetId;
    if (targetId == null) {
      return;
    }
    try {
      await ref.read(sshTargetRepositoryProvider).cancelBootstrap(targetId);
      if (!mounted || _selectedTargetId != targetId) {
        return;
      }
      setState(() => _bootstrapping = false);
    } catch (error) {
      if (!mounted || _selectedTargetId != targetId) {
        return;
      }
      setState(() => _error = error.toString());
    }
  }
}
