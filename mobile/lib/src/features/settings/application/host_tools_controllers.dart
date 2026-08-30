import 'dart:async';

import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/settings/domain/portable_host_settings.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'host_tools_controllers.g.dart';

@riverpod
class SkillRunnerSelection extends _$SkillRunnerSelection {
  @override
  String build(String hostId, String skill) => 'auto';

  void select(String value) {
    state = value;
  }
}

@riverpod
class CliRegistrationController extends _$CliRegistrationController {
  @override
  Future<CliRegistrationStatus> build(String hostId) async {
    final client = await watchHostConnection(ref, hostId);
    if (!client.supportsHostTools) {
      throw UnsupportedError('Update the runtime to manage host tools.');
    }
    return client.cliRegistrationStatus();
  }

  Future<void> install() async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    state = const AsyncLoading<CliRegistrationStatus>();
    state = await AsyncValue.guard(client.installCliRegistration);
  }
}

class const SkillInstallState({
  final String phase = 'idle',
  final String? message,
  final SkillInstallResult? result,
});

@riverpod
class SkillInstallController extends _$SkillInstallController {
  final Logger _logger = Logger('SkillInstallController');
  StreamSubscription<Object?>? _subscription;
  String? _operationId;
  bool _disposed = false;

  @override
  SkillInstallState build(String hostId, String skill) {
    ref.onDispose(() {
      _disposed = true;
      _operationId = null;
      unawaited(_cancelSubscription());
    });
    return const SkillInstallState();
  }

  Future<void> install(String runner) async {
    if (_disposed || state.phase == 'installing') {
      return;
    }
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(hostId).future,
      );
      if (_disposed) {
        return;
      }
      if (!client.supportsHostTools) {
        state = const SkillInstallState(
          phase: 'failed',
          message: 'Update the runtime to install skills.',
        );
        return;
      }
      final operationId = '${DateTime.now().microsecondsSinceEpoch}-$skill';
      _operationId = operationId;
      await _cancelSubscription();
      if (_disposed || _operationId != operationId) {
        return;
      }
      _subscription = client.events.listen((event) {
        if (_disposed ||
            _operationId != operationId ||
            event.name != 'agentSkillInstallProgress' ||
            event.payload['operationId'] != operationId) {
          return;
        }
        state = SkillInstallState(
          phase: event.payload['phase'] as String? ?? 'installing',
          message: event.payload['message'] as String?,
        );
      });
      state = const SkillInstallState(
        phase: 'installing',
        message: 'Installing skill',
      );
      final result = await client.installSkill(
        skill: skill,
        runner: runner,
        operationId: operationId,
      );
      if (!result.succeeded) {
        _logger.warning('skill install failed: ${result.summary}');
      }
      if (_disposed || _operationId != operationId) {
        return;
      }
      state = SkillInstallState(
        phase: result.succeeded ? 'completed' : 'failed',
        message: result.summary,
        result: result,
      );
    } on Object catch (error, stackTrace) {
      _logger.warning('skill install failed', error, stackTrace);
      if (_disposed) {
        return;
      }
      state = SkillInstallState(phase: 'failed', message: error.toString());
    }
  }

  Future<void> _cancelSubscription() async {
    final subscription = _subscription;
    _subscription = null;
    if (subscription == null) {
      return;
    }
    try {
      await subscription.cancel();
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'skill install progress subscription failed to cancel',
        error,
        stackTrace,
      );
    }
  }
}
