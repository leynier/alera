part of 'settings_dialog.dart';

class _RemoteHostSettingsPane extends ConsumerStatefulWidget {
  const _RemoteHostSettingsPane();

  @override
  ConsumerState<_RemoteHostSettingsPane> createState() =>
      _RemoteHostSettingsPaneState();
}

class _RemoteHostSettingsPaneState
    extends ConsumerState<_RemoteHostSettingsPane> {
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
      error: (error, _) => _RemoteHostError(message: error.toString()),
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
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 230,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'SSH Targets',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: AleraTokens.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      AleraIconButton(
                        tooltip: 'New Host',
                        icon: AleraIcons.add,
                        onPressed: _newTarget,
                      ),
                    ],
                  ),
                  const SizedBox(height: AleraTokens.space8),
                  if (targets.isEmpty)
                    const AleraEmptyState(
                      icon: AleraIcons.host,
                      title: 'No Remote Hosts',
                      message: 'Add An SSH Target To Bootstrap A Runtime.',
                    )
                  else
                    AleraPanel(
                      clipBehavior: Clip.antiAlias,
                      children: <Widget>[
                        for (final target in targets)
                          _RemoteHostListRow(
                            target: target,
                            selected: target.id == _selectedTargetId,
                            onTap: () => _selectTarget(target),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: AleraTokens.space16),
            Expanded(
              child: _RemoteHostEditor(
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
            ),
          ],
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
    final editorSignature = _targetEditorSignature(target);
    if (_seededEditorSignature != editorSignature) {
      _aliasController.text = target.alias;
      _hostController.text = target.host;
      _portController.text = target.port.toString();
      _usernameController.text = target.username;
      _installDirController.text = target.installDir ?? '';
      _platform = _normalizedRemoteHostPlatform(target.platform);
      _arch = _normalizedRemoteHostArch(target.arch);
      _authKind = target.authKind;
      _planning = false;
      _plan = null;
      _error = null;
      _seededEditorSignature = editorSignature;
    }

    final statusSignature = _targetStatusSignature(target);
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
            message: _statusLabel(target.bootstrapStatus),
            error: target.lastError,
          );
    _seededStatusSignature = statusSignature;
  }

  String _targetEditorSignature(SshTarget target) {
    return Object.hashAll(<Object?>[
      target.id,
      target.alias,
      target.host,
      target.port,
      target.username,
      target.platform,
      target.arch,
      target.authKind,
      target.installDir,
    ]).toString();
  }

  String _targetStatusSignature(SshTarget target) {
    return Object.hashAll(<Object?>[
      target.id,
      target.runtimeVersion,
      target.runtimePlatform,
      target.runtimeArch,
      target.bootstrapStatus,
      target.lastBootstrapAt,
      target.lastCheckedAt,
      target.lastError,
      target.updatedAt,
    ]).toString();
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
        platform: _emptyToNull(_platform),
        arch: _emptyToNull(_arch),
        authKind: _authKind,
        createdAt: now,
        updatedAt: now,
        installDir: _emptyToNull(_installDirController.text),
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
            installDir: _emptyToNull(_installDirController.text),
            platform: _emptyToNull(_platform),
            arch: _emptyToNull(_arch),
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
            installDir: _emptyToNull(_installDirController.text),
            platform: _emptyToNull(_platform),
            arch: _emptyToNull(_arch),
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

class _RemoteHostListRow extends StatelessWidget {
  const _RemoteHostListRow({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final SshTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AleraTokens.accentSubtle : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Row(
            children: <Widget>[
              Icon(
                AleraIcons.host,
                size: _kSidebarIconSize,
                color: selected
                    ? AleraTokens.foreground
                    : AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      target.alias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.space4),
                    Text(
                      '${target.username}@${target.host}:${target.port}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteHostEditor extends StatelessWidget {
  const _RemoteHostEditor({
    required this.aliasController,
    required this.hostController,
    required this.portController,
    required this.usernameController,
    required this.installDirController,
    required this.platform,
    required this.arch,
    required this.authKind,
    required this.hasSelection,
    required this.saving,
    required this.planning,
    required this.bootstrapping,
    required this.onPlatformChanged,
    required this.onArchChanged,
    required this.onAuthKindChanged,
    required this.onSave,
    required this.onRemove,
    required this.onPlan,
    required this.onBootstrap,
    required this.onCancel,
    this.error,
    this.plan,
    this.progress,
  });

  final TextEditingController aliasController;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController usernameController;
  final TextEditingController installDirController;
  final String platform;
  final String arch;
  final SshAuthKind authKind;
  final bool hasSelection;
  final bool saving;
  final bool planning;
  final bool bootstrapping;
  final ValueChanged<String> onPlatformChanged;
  final ValueChanged<String> onArchChanged;
  final ValueChanged<SshAuthKind> onAuthKindChanged;
  final VoidCallback onSave;
  final VoidCallback? onRemove;
  final VoidCallback? onPlan;
  final VoidCallback? onBootstrap;
  final VoidCallback? onCancel;
  final String? error;
  final SshTargetBootstrapPlan? plan;
  final SshTargetBootstrapProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressError = progress?.error;
    final statusDetail =
        error ??
        progressError ??
        (progress == null ? null : _statusLabel(progress!.status));
    final statusIsError =
        error != null ||
        progressError != null ||
        progress?.status == SshBootstrapStatus.failed;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SettingsGroup(
            title: 'Connection',
            description: 'SSH Target Used By The Runtime Host.',
            children: <Widget>[
              _InlineFieldRow(
                first: AleraTextField(
                  controller: aliasController,
                  labelText: 'Alias',
                  prefixIcon: AleraIcons.text,
                  enabled: !bootstrapping,
                ),
                second: AleraTextField(
                  controller: hostController,
                  labelText: 'Host',
                  prefixIcon: AleraIcons.public,
                  enabled: !bootstrapping,
                ),
              ),
              _InlineFieldRow(
                first: AleraTextField(
                  controller: usernameController,
                  labelText: 'Username',
                  prefixIcon: AleraIcons.ai,
                  enabled: !bootstrapping,
                ),
                second: AleraTextField(
                  controller: portController,
                  labelText: 'Port',
                  keyboardType: TextInputType.number,
                  prefixIcon: AleraIcons.terminal,
                  enabled: !bootstrapping,
                ),
              ),
              _RemoteHostDropdownRow<SshAuthKind>(
                title: 'Authentication',
                value: authKind,
                entries: const <DropdownMenuItem<SshAuthKind>>[
                  DropdownMenuItem<SshAuthKind>(
                    value: SshAuthKind.agent,
                    child: Text('Agent'),
                  ),
                  DropdownMenuItem<SshAuthKind>(
                    value: SshAuthKind.key,
                    child: Text('Key'),
                  ),
                  DropdownMenuItem<SshAuthKind>(
                    value: SshAuthKind.password,
                    enabled: false,
                    child: Text('Password'),
                  ),
                ],
                onChanged: bootstrapping ? null : onAuthKindChanged,
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space16),
          _SettingsGroup(
            title: 'Runtime Bootstrap',
            description: 'Install The Alera Runtime Sidecar On This Host.',
            children: <Widget>[
              _InlineFieldRow(
                first: _RemoteHostDropdownField(
                  label: 'Platform',
                  value: platform,
                  items: const <String, String>{
                    '': 'Auto',
                    'macos': 'macOS',
                    'linux': 'Linux',
                    'windows': 'Windows',
                  },
                  onChanged: bootstrapping ? null : onPlatformChanged,
                ),
                second: _RemoteHostDropdownField(
                  label: 'Architecture',
                  value: arch,
                  items: const <String, String>{
                    '': 'Auto',
                    'x64': 'x64',
                    'arm64': 'arm64',
                  },
                  onChanged: bootstrapping ? null : onArchChanged,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: AleraTextField(
                  controller: installDirController,
                  labelText: 'Install Directory',
                  hintText: 'Default Per Platform',
                  prefixIcon: AleraIcons.folder,
                  enabled: !bootstrapping,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: Wrap(
                  spacing: AleraTokens.space8,
                  runSpacing: AleraTokens.space8,
                  children: <Widget>[
                    ElevatedButton.icon(
                      onPressed: saving || bootstrapping ? null : onSave,
                      icon: Icon(saving ? AleraIcons.loading : AleraIcons.save),
                      label: const Text('Save'),
                    ),
                    OutlinedButton.icon(
                      onPressed: hasSelection && !planning && !bootstrapping
                          ? onPlan
                          : null,
                      icon: Icon(
                        planning ? AleraIcons.loading : AleraIcons.info,
                      ),
                      label: const Text('Plan'),
                    ),
                    OutlinedButton.icon(
                      onPressed: hasSelection && !saving && !bootstrapping
                          ? onBootstrap
                          : null,
                      icon: const Icon(AleraIcons.cloudUpload),
                      label: const Text('Bootstrap'),
                    ),
                    OutlinedButton.icon(
                      onPressed: bootstrapping ? onCancel : null,
                      icon: const Icon(AleraIcons.cancel),
                      label: const Text('Cancel'),
                    ),
                    TextButton.icon(
                      onPressed: saving || bootstrapping ? null : onRemove,
                      icon: const Icon(AleraIcons.delete),
                      label: const Text('Remove'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (plan != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space16),
            _RemoteHostPlanPanel(plan: plan!),
          ],
          if (progress != null || error != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space16),
            AleraPanel(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AleraTokens.space12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        progress?.message ?? 'Remote Runtime Error',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AleraTokens.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AleraTokens.space4),
                      Text(
                        statusDetail ?? 'Remote Runtime Error',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: !statusIsError
                              ? AleraTokens.foregroundMuted
                              : AleraTokens.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineFieldRow extends StatelessWidget {
  const _InlineFieldRow({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        children: <Widget>[
          Expanded(child: first),
          const SizedBox(width: AleraTokens.space12),
          Expanded(child: second),
        ],
      ),
    );
  }
}

class _RemoteHostDropdownRow<T> extends StatelessWidget {
  const _RemoteHostDropdownRow({
    required this.title,
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  final String title;
  final T value;
  final List<DropdownMenuItem<T>> entries;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: DropdownButtonFormField<T>(
        key: ValueKey<String>('$title:$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: title),
        items: entries,
        onChanged: onChanged == null
            ? null
            : (value) {
                if (value != null) {
                  onChanged!(value);
                }
              },
      ),
    );
  }
}

class _RemoteHostDropdownField extends StatelessWidget {
  const _RemoteHostDropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('$label:$value'),
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: <DropdownMenuItem<String>>[
        for (final entry in items.entries)
          DropdownMenuItem<String>(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: onChanged == null ? null : (value) => onChanged!(value ?? ''),
    );
  }
}

class _RemoteHostPlanPanel extends StatelessWidget {
  const _RemoteHostPlanPanel({required this.plan});

  final SshTargetBootstrapPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SettingsGroup(
      title: 'Bootstrap Plan',
      description: '${plan.platform} ${plan.arch} To ${plan.installDir}',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${plan.trust} From ${plan.artifactSource}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AleraTokens.space8),
              for (final step in plan.steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: AleraTokens.space4),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        AleraIcons.check,
                        size: 14,
                        color: AleraTokens.foregroundMuted,
                      ),
                      const SizedBox(width: AleraTokens.space8),
                      Expanded(
                        child: Text(
                          step,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RemoteHostError extends StatelessWidget {
  const _RemoteHostError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AleraEmptyState(
      icon: AleraIcons.error,
      title: 'Remote Hosts Unavailable',
      message: message,
    );
  }
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _normalizedRemoteHostPlatform(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'darwin' || 'mac' || 'macos' => 'macos',
    'linux' => 'linux',
    'win32' || 'windows' || 'windows_nt' => 'windows',
    _ => '',
  };
}

String _normalizedRemoteHostArch(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'x86_64' || 'amd64' || 'x64' => 'x64',
    'aarch64' || 'arm64' => 'arm64',
    _ => '',
  };
}

String _statusLabel(SshBootstrapStatus status) {
  return switch (status) {
    SshBootstrapStatus.notInstalled => 'Not Installed',
    SshBootstrapStatus.planned => 'Planned',
    SshBootstrapStatus.installing => 'Installing',
    SshBootstrapStatus.installed => 'Installed',
    SshBootstrapStatus.failed => 'Failed',
    SshBootstrapStatus.cancelled => 'Cancelled',
  };
}
