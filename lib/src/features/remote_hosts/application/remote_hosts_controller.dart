import 'dart:async';

import 'package:alera/src/features/remote_hosts/application/remote_host_action_result.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/host_link.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_form_values.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_install_steps.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_address.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target_host_os.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'remote_hosts_controller.g.dart';

/// Every remote host with one status each, merged from the stored targets,
/// their links and the install progress this session has seen, plus the
/// actions the Remote Hosts surfaces run.
@Riverpod(keepAlive: true)
class RemoteHostsController extends _$RemoteHostsController {
  final Map<String, RemoteHostInstallProgress> _installs =
      <String, RemoteHostInstallProgress>{};
  final Set<String> _busy = <String>{};
  final Set<String> _installDialogs = <String>{};
  final Map<String, String> _errors = <String, String>{};

  /// Hosts with a running install job, as `sshTarget.bootstrap.jobs` and
  /// later progress events report them. Null until the first list arrives.
  Set<String>? _jobTargetIds;
  RemoteHostCapabilities _capabilities = const RemoteHostCapabilities();
  bool _started = false;

  RuntimeSshTargetRepository get _repository =>
      ref.read(sshTargetRepositoryProvider);

  @override
  RemoteHostsState build() {
    final targets = ref.watch(sshTargetsProvider);
    final links = ref.watch(hostLinksProvider).value;
    ref.listen(sshTargetBootstrapProgressProvider, (_, next) {
      if (next.value case final progress?) {
        _applyProgress(progress);
      }
    });
    if (!_started) {
      _started = true;
      unawaited(_loadRuntimeFacts());
    }
    return _compose(targets, links);
  }

  Future<RemoteHostActionResult> addHost(RemoteHostConnectionValues values) {
    final error = values.validate(existing: _targets);
    if (error != null) {
      return Future<RemoteHostActionResult>.value(
        RemoteHostActionResult(errorMessage: error),
      );
    }
    return _upsert(values.toTarget(now: DateTime.now().toUtc()));
  }

  Future<RemoteHostActionResult> saveConnection(
    String hostId,
    RemoteHostConnectionValues values,
  ) async {
    final existing = _target(hostId);
    if (existing == null) {
      return const RemoteHostActionResult(
        errorMessage: 'This host is no longer registered.',
      );
    }
    final error = values.validate(existing: _targets, editingId: hostId);
    if (error != null) {
      return RemoteHostActionResult(errorMessage: error);
    }
    return _run(hostId, () async {
      final saved = await _repository.upsert(
        values.toTarget(existing: existing, now: DateTime.now().toUtc()),
      );
      return RemoteHostActionResult(target: saved);
    });
  }

  Future<RemoteHostActionResult> saveAdvanced(
    String hostId,
    RemoteHostAdvancedValues values,
  ) async {
    final existing = _target(hostId);
    if (existing == null) {
      return const RemoteHostActionResult(
        errorMessage: 'This host is no longer registered.',
      );
    }
    if (_installs[hostId]?.isRunning ?? false) {
      return const RemoteHostActionResult(
        errorMessage: remoteHostInstallLockedMessage,
      );
    }
    return _run(hostId, () async {
      final saved = await _repository.upsert(
        values.applyTo(existing, now: DateTime.now().toUtc()),
      );
      return RemoteHostActionResult(target: saved);
    });
  }

  Future<RemoteHostActionResult> install(String hostId) {
    return _run(hostId, () async {
      final target = _target(hostId);
      final job = await _repository.startBootstrap(
        targetId: hostId,
        installDir: target?.installDir,
        platform: target?.platform,
        arch: target?.arch,
      );
      _startInstall(hostId, job.jobId, includesRestart: false);
      return const RemoteHostActionResult();
    });
  }

  Future<RemoteHostActionResult> cancelInstall(String hostId) {
    return _run(hostId, () async {
      final target = await _repository.cancelBootstrap(hostId);
      return RemoteHostActionResult(target: target);
    });
  }

  Future<RemoteHostActionResult> connect(String hostId) {
    return _run(hostId, () async {
      await _repository.connectHostLink(hostId);
      return const RemoteHostActionResult();
    });
  }

  Future<RemoteHostActionResult> disconnect(String hostId) {
    return _run(hostId, () async {
      await _repository.disconnectHostLink(hostId);
      return const RemoteHostActionResult();
    });
  }

  /// Reinstalls and restarts the runtime on [hostId]. A busy host fails with
  /// [RemoteHostActionResult.hostBusy] set, so the caller can confirm and
  /// retry with [force].
  Future<RemoteHostActionResult> updateRuntime(
    String hostId, {
    bool force = false,
  }) {
    return _run(hostId, () async {
      if (!await _repository.supportsCapability(
        aleraRuntimeHostRemoteRuntimeUpdateCapability,
      )) {
        return const RemoteHostActionResult(
          errorMessage: remoteHostRuntimeUpdateUnsupportedMessage,
        );
      }
      final job = await _repository.updateRuntime(hostId, force: force);
      _startInstall(hostId, job.jobId, includesRestart: true);
      return const RemoteHostActionResult();
    });
  }

  Future<RemoteHostActionResult> checkConnection(String hostId) {
    return _run(hostId, () async {
      final check = await _repository.checkReachability(hostId);
      return RemoteHostActionResult(target: check.target, check: check);
    });
  }

  /// Forgets [hostId]. A host still in use fails with
  /// [RemoteHostActionResult.inUse] set.
  Future<RemoteHostActionResult> removeHost(String hostId) async {
    final result = await _run(hostId, () async {
      await _repository.remove(hostId);
      return const RemoteHostActionResult();
    });
    if (result.succeeded) {
      _installs.remove(hostId);
      _installDialogs.remove(hostId);
      _errors.remove(hostId);
      _jobTargetIds?.remove(hostId);
      _refresh();
    }
    return result;
  }

  /// Copies the ssh command for [hostId] and returns it.
  Future<RemoteHostActionResult> copySshCommand(String hostId) async {
    final target = _target(hostId);
    if (target == null) {
      return const RemoteHostActionResult(
        errorMessage: 'This host is no longer registered.',
      );
    }
    final command = sshCommandFor(target);
    await Clipboard.setData(ClipboardData(text: command));
    return RemoteHostActionResult(value: command);
  }

  /// While the install dialog shows a host's progress, job cards and the
  /// completion toast stay quiet for it.
  void setInstallDialogOpen(String hostId, {required bool open}) {
    final changed = open
        ? _installDialogs.add(hostId)
        : _installDialogs.remove(hostId);
    if (changed) {
      _refresh();
    }
  }

  /// Drops a failed install this session saw, so the host goes back to Needs
  /// Setup and its failure card disappears.
  void dismissInstallFailure(String hostId) {
    if (_installs[hostId]?.failed ?? false) {
      _installs.remove(hostId);
      _refresh();
    }
  }

  void clearError(String hostId) {
    if (_errors.remove(hostId) != null) {
      _refresh();
    }
  }

  List<SshTarget> get _targets =>
      ref.read(sshTargetsProvider).value ?? const <SshTarget>[];

  SshTarget? _target(String hostId) {
    for (final target in _targets) {
      if (target.id == hostId) {
        return target;
      }
    }
    return null;
  }

  Future<RemoteHostActionResult> _upsert(SshTarget target) {
    return _run(target.id, () async {
      final saved = await _repository.upsert(target);
      return RemoteHostActionResult(target: saved);
    });
  }

  Future<RemoteHostActionResult> _run(
    String hostId,
    Future<RemoteHostActionResult> Function() action,
  ) async {
    _busy.add(hostId);
    _errors.remove(hostId);
    _refresh();
    RemoteHostActionResult result;
    try {
      result = await action();
    } on Object catch (error) {
      result = RemoteHostActionResult.failure(error);
    }
    _busy.remove(hostId);
    if (result.errorMessage case final message?) {
      _errors[hostId] = message;
    }
    _refresh();
    return result;
  }

  void _startInstall(
    String hostId,
    String jobId, {
    required bool includesRestart,
  }) {
    final current = _installs[hostId];
    if (current != null && current.jobId == jobId && current.isRunning) {
      return;
    }
    _installs[hostId] = RemoteHostInstallProgress(
      targetId: hostId,
      jobId: jobId,
      includesRestart: includesRestart,
    );
    _jobTargetIds?.add(hostId);
  }

  void _applyProgress(SshTargetBootstrapProgress progress) {
    final hostId = progress.targetId;
    final current = _installs[hostId];
    _installs[hostId] = current == null
        ? RemoteHostInstallProgress.fromProgress(progress)
        : current.apply(progress);
    if (progress.status == SshBootstrapStatus.installing) {
      _jobTargetIds?.add(hostId);
    } else {
      _jobTargetIds?.remove(hostId);
    }
    _refresh();
  }

  /// Recovers installs that were already running when this app attached, and
  /// learns which remote host features the runtime offers.
  Future<void> _loadRuntimeFacts() async {
    final repository = _repository;
    try {
      final results = await Future.wait<bool>(<Future<bool>>[
        repository.supportsHostLinks(),
        repository.supportsCapability(
          aleraRuntimeHostRemoteHostStatusCapability,
        ),
        repository.supportsCapability(
          aleraRuntimeHostRemoteRuntimeUpdateCapability,
        ),
        repository.supportsCapability(
          aleraRuntimeHostSshTargetIdentityFileCapability,
        ),
      ]);
      _capabilities = RemoteHostCapabilities(
        hostLinks: results[0],
        hostStatus: results[1],
        runtimeUpdate: results[2],
        identityFile: results[3],
      );
    } on Object {
      // Capabilities stay off: the UI then hides what it cannot offer.
    }
    try {
      final jobs = await repository.listBootstrapJobs();
      final running = <String>{};
      for (final job in jobs) {
        if (job.status != SshBootstrapStatus.installing) {
          continue;
        }
        running.add(job.targetId);
        final current = _installs[job.targetId];
        if (current == null || current.jobId != job.jobId) {
          _installs[job.targetId] = RemoteHostInstallProgress.fromJob(job);
        }
      }
      _jobTargetIds = running;
    } on Object {
      // Without the list an install marked in the store keeps showing as
      // Installing rather than guessing that it was interrupted.
    }
    if (ref.mounted) {
      _refresh();
    }
  }

  void _refresh() {
    if (!ref.mounted) {
      return;
    }
    state = _compose(
      ref.read(sshTargetsProvider),
      ref.read(hostLinksProvider).value,
    );
  }

  RemoteHostsState _compose(
    AsyncValue<List<SshTarget>> targets,
    List<HostLinkState>? links,
  ) {
    final linksById = hostLinkStatesById(links ?? const <HostLinkState>[]);
    final list = targets.value ?? const <SshTarget>[];
    return RemoteHostsState(
      hosts: <RemoteHostView>[
        for (final target in list) _view(target, linksById[target.id]),
      ],
      loading: targets.isLoading && !targets.hasValue,
      loadError: targets.hasError && !targets.hasValue
          ? remoteHostErrorMessage(targets.error!)
          : null,
      busyHostIds: Set<String>.unmodifiable(_busy),
      installDialogHostIds: Set<String>.unmodifiable(_installDialogs),
      capabilities: _capabilities,
    );
  }

  RemoteHostView _view(SshTarget target, HostLinkState? link) {
    final install = _installs[target.id];
    return RemoteHostView(
      target: target,
      status: _status(target, link, install),
      os: sshTargetHostOs(target),
      address: sshAddressLabel(target),
      busy: _busy.contains(target.id),
      installProgress: install,
      link: link,
      actionError: _errors[target.id],
    );
  }

  RemoteHostStatus _status(
    SshTarget target,
    HostLinkState? link,
    RemoteHostInstallProgress? install,
  ) {
    final reported = target.hostStatus;
    if (reported != null) {
      // The runtime reports a failed install as Needs Setup; this session
      // keeps it as an install error until the user dismisses it.
      if (install != null &&
          install.failed &&
          reported is RemoteHostNeedsSetup) {
        return RemoteHostError(
          detail:
              install.error ??
              reported.detail ??
              target.lastError ??
              'The Alera runtime install failed.',
          origin: RemoteHostErrorOrigin.install,
        );
      }
      return reported;
    }
    final jobs = _jobTargetIds;
    return RemoteHostStatus.derive(
      target,
      link,
      install?.toBootstrapProgress(),
      hasInstallJob: jobs?.contains(target.id),
    );
  }
}
