import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/feedback/alera_progress_steps.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_action_result.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_check_result.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/presentation/add_remote_host_install_summary.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_advanced_group.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_install_progress.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_runtime_update_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _Next { install, update, connect, proceed }

/// Add Host step 2: checks the connection, shows what will be installed, then
/// follows the install. Close leaves a running install going.
class const AddRemoteHostInstallStep({
  super.key,
  required final String hostId,
  required final VoidCallback onBack,
  required final VoidCallback onClose,
  required final VoidCallback onFinished,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AddRemoteHostInstallStep> createState() =>
      _AddRemoteHostInstallStepState();
}

class _AddRemoteHostInstallStepState
    extends ConsumerState<AddRemoteHostInstallStep> {
  late final RemoteHostsController _controller = ref.read(
    remoteHostsControllerProvider.notifier,
  );
  RemoteHostAdvancedDraft? _draft;
  bool _checking = true;
  String? _checkError;
  RemoteHostCheckResult? _check;
  SshTargetBootstrapPlan? _plan;
  String? _actionError;
  bool _starting = false;
  bool _installStarted = false;

  @override
  void initState() {
    super.initState();
    final controller = _controller;
    final hostId = widget.hostId;
    // Providers may not change while the tree builds.
    unawaited(
      Future<void>.microtask(
        () => controller.setInstallDialogOpen(hostId, open: true),
      ),
    );
    unawaited(_runChecks());
  }

  @override
  void dispose() {
    final controller = _controller;
    final hostId = widget.hostId;
    unawaited(
      Future<void>.microtask(
        () => controller.setInstallDialogOpen(hostId, open: false),
      ),
    );
    _draft?.dispose();
    super.dispose();
  }

  Future<void> _runChecks() async {
    // Runs from initState too, where neither setState nor a provider change
    // is allowed yet.
    await Future.pause(Duration.zero);
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = true;
      _checkError = null;
    });
    final hostId = widget.hostId;
    final state = ref.read(remoteHostsControllerProvider);
    final target = state.hostById(hostId)?.target;
    final repository = ref.read(sshTargetRepositoryProvider);
    final planFuture = repository
        .bootstrapPlan(
          targetId: hostId,
          installDir: target?.installDir,
          platform: target?.platform,
          arch: target?.arch,
        )
        .then<SshTargetBootstrapPlan?>((plan) => plan, onError: (_) => null);
    String? error;
    RemoteHostCheckResult? check;
    if (state.capabilities.hostStatus) {
      final result = await _controller.checkConnection(hostId);
      check = result.check;
      if (!result.succeeded) {
        error = result.errorMessage;
        _controller.clearError(hostId);
      } else if (check != null && !check.reachable) {
        error =
            check.target.lastError ??
            'Alera could not reach ${check.target.host} over SSH.';
      }
    }
    final plan = await planFuture;
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      _check = check;
      _checkError = error;
      _plan = plan;
    });
  }

  _Next _next(RemoteHostView host, RemoteHostCapabilities capabilities) {
    final installed =
        _check?.runtimeInstalled ??
        host.target.bootstrapStatus == SshBootstrapStatus.installed;
    if (!installed) {
      return _Next.install;
    }
    final status = host.status;
    if (status is RemoteHostConnected &&
        status.updateAvailable &&
        capabilities.runtimeUpdate) {
      return _Next.update;
    }
    return capabilities.hostLinks ? _Next.connect : _Next.proceed;
  }

  Future<void> _run(_Next next, RemoteHostView host) async {
    setState(() {
      _starting = true;
      _actionError = null;
    });
    final hostId = widget.hostId;
    var succeeded = true;
    String? error;
    final draft = _draft;
    if (draft != null && draft.isDirty) {
      final saved = await _controller.saveAdvanced(hostId, draft.values);
      if (saved.target case final target?) {
        draft.syncFrom(target);
      }
      succeeded = saved.succeeded;
      error = saved.errorMessage;
    }
    if (succeeded) {
      final result = switch (next) {
        _Next.install => await _install(hostId),
        _Next.update =>
          mounted ? await updateRemoteHostRuntime(context, ref, hostId) : null,
        _Next.connect => await _controller.connect(hostId),
        _Next.proceed => null,
      };
      succeeded = result?.succeeded ?? true;
      error = result?.errorMessage;
      if (succeeded && result?.hostBusy == null) {
        if (next == _Next.connect || next == _Next.proceed) {
          widget.onFinished();
        } else {
          _installStarted = true;
        }
      }
    }
    if (!succeeded) {
      _controller.clearError(hostId);
    }
    if (mounted) {
      setState(() {
        _starting = false;
        _actionError = succeeded ? null : error;
      });
    }
  }

  Future<void> _saveDraft() async {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    setState(() => _starting = true);
    final saved = await _controller.saveAdvanced(widget.hostId, draft.values);
    if (saved.target case final target?) {
      draft.syncFrom(target);
    }
    if (mounted) {
      setState(() {
        _starting = false;
        _actionError = saved.errorMessage;
      });
    }
  }

  Future<RemoteHostActionResult> _install(String hostId) {
    _controller.dismissInstallFailure(hostId);
    return _controller.install(hostId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(remoteHostsControllerProvider);
    final host = state.hostById(widget.hostId);
    ref.listen(remoteHostsControllerProvider, (_, next) {
      if (next.hostById(widget.hostId) case final host?) {
        _draft?.syncFrom(host.target);
      }
    });
    ref.listen<bool>(
      remoteHostsControllerProvider.select(
        (state) =>
            state.hostById(widget.hostId)?.installProgress?.succeeded ?? false,
      ),
      (previous, next) {
        if (next && previous != true && _installStarted) {
          widget.onFinished();
        }
      },
    );
    if (host == null) {
      return const AleraInlineNotice(
        message: 'This host is no longer registered.',
        tone: .error,
      );
    }
    final progress = host.installProgress;
    final installing =
        host.status is RemoteHostInstalling ||
        (_installStarted && progress != null && !progress.succeeded);
    final body = installing
        ? _installingBody(host)
        : _summaryBody(host, state.capabilities);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Flexible(child: SingleChildScrollView(child: body)),
        if (_actionError case final error?) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          AleraInlineNotice(message: error, tone: .error),
        ],
        const SizedBox(height: AleraTokens.space20),
        installing
            ? _installingFooter(host)
            : _summaryFooter(host, state.capabilities),
      ],
    );
  }

  Widget _installingBody(RemoteHostView host) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Text(
          'Installing Alera runtime on ${host.alias}',
          style: theme.textTheme.titleSmall?.copyWith(
            color: AleraTokens.foreground,
            fontWeight: .w600,
          ),
        ),
        const SizedBox(height: AleraTokens.space12),
        AleraProgressSteps(
          steps: remoteHostInstallProgressSteps(
            host.installProgress,
            targetId: host.id,
          ),
        ),
      ],
    );
  }

  Widget _installingFooter(RemoteHostView host) {
    final progress = host.installProgress;
    final ended = progress != null && !progress.isRunning;
    return Row(
      mainAxisAlignment: .end,
      children: <Widget>[
        if (ended)
          FilledButton(
            onPressed: _starting
                ? null
                : () => unawaited(_run(_Next.install, host)),
            child: const Text('Retry'),
          )
        else
          OutlinedButton(
            onPressed: host.busy
                ? null
                : () => unawaited(_controller.cancelInstall(host.id)),
            child: const Text('Cancel Install'),
          ),
        const SizedBox(width: AleraTokens.space8),
        TextButton(onPressed: widget.onClose, child: const Text('Close')),
      ],
    );
  }

  Widget _summaryBody(
    RemoteHostView host,
    RemoteHostCapabilities capabilities,
  ) {
    final draft = _draft ??= RemoteHostAdvancedDraft(host.target);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (capabilities.hostStatus) ...<Widget>[
          AleraSettingsGroup(
            title: 'Connection',
            trailing: TextButton(
              onPressed: _checking ? null : () => unawaited(_runChecks()),
              child: const Text('Re-check'),
            ),
            children: <Widget>[_connectionBlock(host)],
          ),
          const SizedBox(height: AleraTokens.space16),
        ],
        AleraSettingsGroup(
          title: 'What Will Be Installed',
          children: <Widget>[
            RemoteHostInstallPlanRows(plan: _plan, loading: _checking),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        RemoteHostAdvancedGroup(
          draft: draft,
          locked: false,
          saving: _starting,
          identityFileSupported: capabilities.identityFile,
          onSave: () => unawaited(_saveDraft()),
        ),
      ],
    );
  }

  Widget _connectionBlock(RemoteHostView host) {
    if (_checking) {
      return const RemoteHostCheckLine(
        icon: AleraIcons.loading,
        text: 'Checking the connection…',
      );
    }
    if (_checkError case final error?) {
      return Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: AleraInlineNotice(
          message: error,
          tone: .error,
          child: Wrap(
            spacing: AleraTokens.space8,
            children: <Widget>[
              FilledButton(
                onPressed: () => unawaited(_runChecks()),
                child: const Text('Retry'),
              ),
              TextButton(onPressed: widget.onBack, child: const Text('Back')),
            ],
          ),
        ),
      );
    }
    final target = _check?.target ?? host.target;
    final platform = host.platformLabel;
    final version = target.runtimeVersion;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        RemoteHostCheckLine(
          icon: AleraIcons.check,
          text: <String>[
            'Reached ${target.host} as ${target.username}',
            ?platform,
          ].join(' · '),
        ),
        RemoteHostCheckLine(
          icon: AleraIcons.check,
          text: _check?.runtimeInstalled ?? false
              ? (version == null
                    ? 'Alera runtime already installed'
                    : 'Alera runtime $version already installed')
              : 'No Alera runtime installed',
        ),
      ],
    );
  }

  Widget _summaryFooter(
    RemoteHostView host,
    RemoteHostCapabilities capabilities,
  ) {
    final next = _next(host, capabilities);
    final blocked = _checking || _checkError != null || _starting;
    return Row(
      mainAxisAlignment: .end,
      children: <Widget>[
        TextButton(onPressed: widget.onBack, child: const Text('Back')),
        const SizedBox(width: AleraTokens.space8),
        FilledButton(
          onPressed: blocked ? null : () => unawaited(_run(next, host)),
          child: Text(switch (next) {
            _Next.install => 'Install Runtime',
            _Next.update => 'Update Runtime',
            _Next.connect => 'Connect',
            _Next.proceed => 'Continue',
          }),
        ),
      ],
    );
  }
}
