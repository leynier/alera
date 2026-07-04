import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_editor.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_field_normalizers.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_list_row.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_target_signatures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RemoteHostSettingsPane extends ConsumerStatefulWidget {
  const RemoteHostSettingsPane({super.key});

  @override
  ConsumerState<RemoteHostSettingsPane> createState() =>
      _RemoteHostSettingsPaneState();
}

class _RemoteHostSettingsPaneState
    extends ConsumerState<RemoteHostSettingsPane> {
  final TextEditingController _aliasController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '22',
  );
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _installDirController = TextEditingController();
  String? _selectedTargetId;
  bool _creatingNew = false;
  String _platform = '';
  String _arch = '';
  SshAuthKind _authKind = SshAuthKind.agent;
  String? _error;
  SshTargetBootstrapPlan? _plan;
  SshTargetBootstrapProgress? _progress;
  bool _saving = false;
  bool _planning = false;
  bool _bootstrapping = false;
  String? _seededEditorSignature;
  String? _seededStatusSignature;

  @override
  void dispose() {
    _aliasController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _installDirController.dispose();
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
                  title: 'No Remote Hosts',
                  message: 'Add An SSH Target To Bootstrap A Runtime.',
                )
              : SingleChildScrollView(
                  child: AleraPanel(
                    clipBehavior: Clip.antiAlias,
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
            aliasController: _aliasController,
            hostController: _hostController,
            portController: _portController,
            usernameController: _usernameController,
            installDirController: _installDirController,
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
          ),
        );
      },
    );
  }

  SshTarget? _selectedTarget(List<SshTarget> targets) {
    final selectedId = _selectedTargetId;
    if (selectedId == null) {
      return null;
    }
    for (final target in targets) {
      if (target.id == selectedId) {
        return target;
      }
    }
    return null;
  }

  void _seedFromTarget(SshTarget target) {
    final editorSignature = remoteHostEditorSignature(target);
    if (_seededEditorSignature != editorSignature) {
      _aliasController.text = target.alias;
      _hostController.text = target.host;
      _portController.text = target.port.toString();
      _usernameController.text = target.username;
      _installDirController.text = target.installDir ?? '';
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
    _aliasController.clear();
    _hostController.clear();
    _portController.text = '22';
    _usernameController.clear();
    _installDirController.clear();
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
    final alias = _aliasController.text.trim();
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final port = _validatedPort();
    if (port == null) {
      return null;
    }
    if (alias.isEmpty || host.isEmpty || username.isEmpty) {
      setState(() => _error = 'Alias, Host, And Username Are Required');
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
        installDir: emptyToNull(_installDirController.text),
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
    final value = _portController.text.trim();
    if (value.isEmpty) {
      return 22;
    }
    final port = int.tryParse(value);
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Port Must Be Between 1 And 65535');
      return null;
    }
    return port;
  }

  bool _targetMutationLocked() {
    if (!_bootstrapping) {
      return false;
    }
    setState(() {
      _error = 'Cancel Or Wait For Bootstrap Before Changing This Host';
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
            installDir: emptyToNull(_installDirController.text),
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
            installDir: emptyToNull(_installDirController.text),
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
          message: 'Remote Runtime Install Started',
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
