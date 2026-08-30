import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/mobile_emulator/application/mobile_emulator_lease_coordinator.dart';
import 'package:alera/src/features/mobile_emulator/application/mobile_emulator_providers.dart';
import 'package:alera/src/features/mobile_emulator/domain/mobile_emulator_models.dart';
import 'package:alera/src/features/mobile_emulator/infra/mobile_emulator_service.dart';
import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_keyboard_input.dart';
import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_playback_monitor.dart';
import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_pointer_controller.dart';
import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_surface_status.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

final Logger _log = Logger('MobileEmulatorSurface');

class const MobileEmulatorSurface({
  super.key,
  required final Workspace workspace,
  required final WorkspaceTabRecord tab,
  required final bool autofocus,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<MobileEmulatorSurface> createState() =>
      _MobileEmulatorSurfaceState();
}

class _MobileEmulatorSurfaceState extends ConsumerState<MobileEmulatorSurface>
    with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Mobile Emulator');
  late final MobileEmulatorLeaseCoordinator _leases;
  late final MobileEmulatorService _service;
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<VideoParams>? _videoParamsSubscription;
  MobileEmulatorPlaybackMonitor? _playbackMonitor;
  StreamSubscription<Object?>? _changeSubscription;
  Timer? _hiddenTimer;
  final MobileEmulatorPlaybackRecoveryPolicy _playbackRecovery =
      MobileEmulatorPlaybackRecoveryPolicy();
  late final MobileEmulatorPointerController _pointerController =
      MobileEmulatorPointerController(onPointer: _sendPointer);
  double? _decodedAspectRatio;
  MobileEmulatorSession? _session;
  Future<void>? _pendingAcquire;
  int? _pendingAcquireGeneration;
  String? _pendingAcquireTabId;
  Object? _error;
  bool _loading = true;
  bool _leaseHeld = false;
  bool _wantsLease = true;
  int _leaseGeneration = 0;

  MobileEmulatorTarget get _target => MobileEmulatorTarget(
    tabId: widget.tab.id,
    workspaceId: widget.workspace.id,
  );
  @override
  void initState() {
    super.initState();
    _leases = ref.read(mobileEmulatorLeaseCoordinatorProvider);
    _service = ref.read(mobileEmulatorServiceProvider);
    WidgetsBinding.instance.addObserver(this);
    _changeSubscription = _service.changes.listen(_handleRuntimeChange);
    unawaited(_acquire());
  }

  @override
  void didUpdateWidget(covariant MobileEmulatorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id) {
      _playbackRecovery.reset();
      _pointerController.finish();
      _wantsLease = false;
      _leaseGeneration += 1;
      if (_leaseHeld) {
        _leases.release(oldWidget.tab.id);
      }
      _leaseHeld = false;
      _session = null;
      unawaited(_disposePlayer());
      unawaited(_acquire());
    }
  }

  Future<void> _acquire({bool showLoading = true}) {
    _hiddenTimer?.cancel();
    _wantsLease = true;
    final target = _target;
    final generation = _leaseGeneration;
    final pending = _pendingAcquire;
    if (pending != null) {
      if (_pendingAcquireGeneration == generation &&
          _pendingAcquireTabId == target.tabId) {
        return pending;
      }
      return pending.catchError((_) {}).then<void>((_) async {
        if (mounted && _wantsLease && !_leaseHeld) {
          await _acquire(showLoading: showLoading);
        }
      });
    }
    if (mounted && showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final alreadyHeld = _leaseHeld;
    late final Future<void> next;
    next =
        _performAcquire(
          target: target,
          generation: generation,
          alreadyHeld: alreadyHeld,
        ).whenComplete(() {
          if (identical(_pendingAcquire, next)) {
            _pendingAcquire = null;
            _pendingAcquireGeneration = null;
            _pendingAcquireTabId = null;
          }
        });
    _pendingAcquire = next;
    _pendingAcquireGeneration = generation;
    _pendingAcquireTabId = target.tabId;
    return next;
  }

  Future<void> _performAcquire({
    required MobileEmulatorTarget target,
    required int generation,
    required bool alreadyHeld,
  }) async {
    try {
      final session = alreadyHeld
          ? await _leases.refresh(target)
          : await _leases.acquire(target);
      if (!_isCurrentLeaseRequest(target, generation)) {
        if (!alreadyHeld) {
          _leases.release(target.tabId);
        }
        return;
      }
      _leaseHeld = true;
      await _showSession(session, target, generation);
    } catch (error) {
      if (_isCurrentLeaseRequest(target, generation)) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  bool _isCurrentLeaseRequest(MobileEmulatorTarget target, int generation) =>
      mounted &&
      _wantsLease &&
      generation == _leaseGeneration &&
      target.tabId == widget.tab.id;

  Future<void> _showSession(
    MobileEmulatorSession session,
    MobileEmulatorTarget target,
    int generation,
  ) async {
    if (!_isCurrentLeaseRequest(target, generation)) {
      return;
    }
    final stream = session.stream;
    if (stream == null) {
      if (_isCurrentLeaseRequest(target, generation)) {
        setState(() {
          _session = session;
          _loading = session.state == 'starting';
          _error = session.state == 'failed'
              ? 'The mobile emulator failed to start.'
              : null;
        });
      }
      return;
    }
    final currentUrl = _session?.stream?.url;
    if (_player == null || currentUrl != stream.url) {
      await _disposePlayer();
      MediaKit.ensureInitialized();
      final player = Player();
      final controller = VideoController(player);
      final playbackMonitor = MobileEmulatorPlaybackMonitor(
        errors: player.stream.error,
        completions: player.stream.completed,
        onWarning: (_) =>
            _log.warning('Emulator playback warning for tab ${target.tabId}.'),
        onFailure: () => _handlePlaybackFailure(player),
      );
      final videoParamsSubscription = player.stream.videoParams.listen((
        params,
      ) {
        if (!identical(_player, player)) {
          return;
        }
        final aspectRatio = mobileEmulatorDecodedAspectRatio(
          width: params.dw,
          height: params.dh,
          rotation: params.rotate,
        );
        if (aspectRatio == null || aspectRatio == _decodedAspectRatio) {
          return;
        }
        if (mounted) {
          setState(() {
            _decodedAspectRatio = aspectRatio;
          });
        }
      });
      try {
        await player.open(Media(stream.url.toString()), play: true);
      } catch (_) {
        await playbackMonitor.dispose();
        await videoParamsSubscription.cancel();
        await player.dispose();
        rethrow;
      }
      if (!_isCurrentLeaseRequest(target, generation)) {
        await playbackMonitor.dispose();
        await videoParamsSubscription.cancel();
        await player.dispose();
        return;
      }
      _player = player;
      _videoController = controller;
      _videoParamsSubscription = videoParamsSubscription;
      _playbackMonitor = playbackMonitor;
      _playbackRecovery.playbackStarted();
      final params = player.state.videoParams;
      _decodedAspectRatio = mobileEmulatorDecodedAspectRatio(
        width: params.dw,
        height: params.dh,
        rotation: params.rotate,
      );
    }
    if (_isCurrentLeaseRequest(target, generation)) {
      setState(() {
        _session = session;
        _loading = false;
        _error = null;
      });
      if (widget.autofocus) {
        _focusNode.requestFocus();
      }
    }
  }

  void _handlePlaybackFailure(Player player) {
    if (!identical(_player, player) || !_wantsLease || !_leaseHeld) {
      return;
    }
    _pointerController.finish();
    _session = null;
    switch (_playbackRecovery.recordFailure()) {
      case MobileEmulatorPlaybackRecoveryAction.retry:
        unawaited(_disposePlayer().then((_) => _acquire(showLoading: false)));
      case MobileEmulatorPlaybackRecoveryAction.fail:
        _wantsLease = false;
        _leaseGeneration += 1;
        _leaseHeld = false;
        unawaited(
          _disposePlayer().then(
            (_) => _leases.suspend(widget.tab.id).catchError((_) {}),
          ),
        );
        if (mounted) {
          setState(() {
            _loading = false;
            _error = const MobileEmulatorException(
              code: 'playback_unstable',
              message: 'The mobile emulator stream became unstable.',
              nextSteps: <String>[
                'The Android device was left running. Select Retry to reconnect.',
              ],
            );
          });
        }
    }
  }

  Future<void> _retryPlayback() {
    _playbackRecovery.reset();
    return _acquire();
  }

  void _handleRuntimeChange(Object? rawEvent) {
    if (rawEvent is! RuntimeHostEvent) {
      return;
    }
    if (rawEvent.name == aleraRuntimeHostConnectedEvent) {
      _playbackRecovery.reset();
      _wantsLease = true;
      _leaseGeneration += 1;
      _leaseHeld = false;
      _leases.invalidate(widget.tab.id);
      unawaited(_disposePlayer());
      unawaited(_acquire());
      return;
    }
    final eventTabId = rawEvent.payload['tabId'];
    if (eventTabId != null && eventTabId != widget.tab.id) {
      return;
    }
    final rawReason = rawEvent.payload['reason'];
    final action = resolveMobileEmulatorRuntimeChange(
      reason: rawReason is String ? rawReason : null,
      leaseHeld: _leaseHeld,
    );
    switch (action) {
      case MobileEmulatorRuntimeChangeAction.ignore:
        return;
      case MobileEmulatorRuntimeChangeAction.stopped:
        _playbackRecovery.reset();
        _wantsLease = false;
        _leaseGeneration += 1;
        _leaseHeld = false;
        _leases.invalidate(widget.tab.id);
        unawaited(_disposePlayer());
        if (mounted) {
          setState(() {
            _loading = false;
            _session = null;
            _error = const MobileEmulatorException(
              code: 'emulator_stopped',
              message: 'The mobile emulator was stopped.',
            );
          });
        }
      case MobileEmulatorRuntimeChangeAction.refresh:
        unawaited(_acquire(showLoading: false));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _hiddenTimer?.cancel();
      if (!_leaseHeld) {
        unawaited(_acquire());
      }
      return;
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _hiddenTimer?.cancel();
      _hiddenTimer = Timer(const Duration(milliseconds: 500), () {
        _pointerController.finish();
        _wantsLease = false;
        _leaseGeneration += 1;
        if (_leaseHeld) {
          _leaseHeld = false;
          unawaited(_leases.suspend(widget.tab.id).catchError((_) {}));
        }
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final key = mobileEmulatorInteractiveKey(
      logicalKey: event.logicalKey,
      controlPressed: keyboard.isControlPressed,
      metaPressed: keyboard.isMetaPressed,
      altPressed: keyboard.isAltPressed,
      shiftPressed: keyboard.isShiftPressed,
    );
    if (key != null) {
      unawaited(_service.key(target: _target, key: key).catchError((_) {}));
      return KeyEventResult.handled;
    }
    final character = mobileEmulatorPrintableText(
      character: event.character,
      controlPressed: keyboard.isControlPressed,
      metaPressed: keyboard.isMetaPressed,
      altPressed: keyboard.isAltPressed,
    );
    if (character == null) {
      return KeyEventResult.ignored;
    }
    unawaited(
      _service.typeText(target: _target, text: character).catchError((_) {}),
    );
    return KeyEventResult.handled;
  }

  void _sendPointer(String type, Offset position, MobileEmulatorTarget target) {
    unawaited(
      _service
          .pointer(target: target, type: type, x: position.dx, y: position.dy)
          .catchError((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) {
      return MobileEmulatorFailure(error: error, onRetry: _retryPlayback);
    }
    if (_loading || _videoController == null) {
      return MobileEmulatorLoading(state: _session?.state);
    }
    return ColoredBox(
      color: AleraTokens.bg,
      child: Center(
        child: AspectRatio(
          aspectRatio:
              _decodedAspectRatio ??
              mobileEmulatorStreamAspectRatio(_session?.stream),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return Focus(
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                onKeyEvent: _handleKeyEvent,
                child: Listener(
                  behavior: .opaque,
                  onPointerDown: (event) {
                    _pointerController.down(
                      event,
                      size,
                      target: _target,
                      requestFocus: _focusNode.requestFocus,
                    );
                  },
                  onPointerMove: (event) =>
                      _pointerController.move(event, size),
                  onPointerUp: (event) => _pointerController.end(event, size),
                  onPointerCancel: (event) =>
                      _pointerController.end(event, size),
                  child: Video(
                    controller: _videoController!,
                    fit: .contain,
                    controls: NoVideoControls,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _disposePlayer() async {
    final player = _player;
    final playbackMonitor = _playbackMonitor;
    final videoParamsSubscription = _videoParamsSubscription;
    _player = null;
    _videoController = null;
    _playbackMonitor = null;
    _videoParamsSubscription = null;
    _decodedAspectRatio = null;
    await playbackMonitor?.dispose();
    await videoParamsSubscription?.cancel();
    if (player != null) {
      await player.dispose();
    }
  }

  @override
  void dispose() {
    _wantsLease = false;
    _leaseGeneration += 1;
    _playbackRecovery.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _hiddenTimer?.cancel();
    _pointerController.finish();
    unawaited(_changeSubscription?.cancel());
    if (_leaseHeld) {
      _leases.release(widget.tab.id);
    }
    unawaited(_disposePlayer());
    _focusNode.dispose();
    super.dispose();
  }
}
