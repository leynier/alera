import 'dart:async';

import 'package:alera/src/features/ai_dictation/application/ai_dictation_providers.dart';
import 'package:alera/src/features/ai_dictation/infra/ai_dictation_model_store.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_dictation_model_transfers.g.dart';

enum AiDictationModelTransferStatus {
  idle,
  queued,
  downloading,
  verifying,
  resumable,
  failed,
}

class AiDictationModelTransfer {
  const AiDictationModelTransfer({
    this.status = AiDictationModelTransferStatus.idle,
    this.installed = false,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.message,
  });

  final AiDictationModelTransferStatus status;
  final bool installed;
  final int receivedBytes;
  final int totalBytes;
  final String? message;

  double get progress =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0, 1).toDouble();

  AiDictationModelTransfer copyWith({
    AiDictationModelTransferStatus? status,
    bool? installed,
    int? receivedBytes,
    int? totalBytes,
    String? message,
    bool clearMessage = false,
  }) => AiDictationModelTransfer(
    status: status ?? this.status,
    installed: installed ?? this.installed,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    message: clearMessage ? null : message ?? this.message,
  );
}

class AiDictationModelTransfersState {
  const AiDictationModelTransfersState({
    required this.models,
    this.initialized = false,
    this.activeModelId,
  });

  final Map<String, AiDictationModelTransfer> models;
  final bool initialized;
  final String? activeModelId;

  AiDictationModelTransfer forModel(String id) =>
      models[AiDictationModelStore.modelForId(id)] ??
      const AiDictationModelTransfer();

  AiDictationModelTransfersState copyWith({
    Map<String, AiDictationModelTransfer>? models,
    bool? initialized,
    String? activeModelId,
    bool clearActiveModel = false,
  }) => AiDictationModelTransfersState(
    models: models ?? this.models,
    initialized: initialized ?? this.initialized,
    activeModelId: clearActiveModel
        ? null
        : activeModelId ?? this.activeModelId,
  );
}

final _log = Logger('AiDictationModelTransfers');

@Riverpod(keepAlive: true)
class AiDictationModelTransfers extends _$AiDictationModelTransfers {
  bool _disposed = false;
  final List<String> _queue = <String>[];

  AiDictationModelStore get _store => ref.read(aiDictationModelStoreProvider);

  @override
  AiDictationModelTransfersState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(_initialize));
    return AiDictationModelTransfersState(
      models: <String, AiDictationModelTransfer>{
        for (final model in AiDictationModelStore.models)
          model.id: AiDictationModelTransfer(totalBytes: model.sizeBytes),
      },
    );
  }

  Future<void> _initialize() async {
    await refresh();
    if (_disposed) return;
    state = state.copyWith(initialized: true);
    for (final id in await _store.resumeIntentIds()) {
      if (_disposed) return;
      await download(id, automatic: true);
    }
  }

  Future<void> refresh() async {
    final updated = <String, AiDictationModelTransfer>{};
    for (final model in AiDictationModelStore.models) {
      final current = state.forModel(model.id);
      final installed = await _store.isInstalled(model.id);
      final partial = await _store.partialBytes(model.id);
      final status = state.activeModelId == model.id
          ? current.status
          : installed
          ? AiDictationModelTransferStatus.idle
          : partial > 0
          ? AiDictationModelTransferStatus.resumable
          : current.status == AiDictationModelTransferStatus.failed
          ? current.status
          : AiDictationModelTransferStatus.idle;
      updated[model.id] = current.copyWith(
        installed: installed,
        receivedBytes: installed ? model.sizeBytes : partial,
        totalBytes: model.sizeBytes,
        status: status,
      );
    }
    if (!_disposed) state = state.copyWith(models: updated);
  }

  Future<void> download(String id, {bool automatic = false}) async {
    final normalized = AiDictationModelStore.modelForId(id);
    if (state.activeModelId != null) {
      if (!_queue.contains(normalized)) {
        _queue.add(normalized);
        _update(
          normalized,
          state
              .forModel(normalized)
              .copyWith(
                status: AiDictationModelTransferStatus.queued,
                clearMessage: true,
              ),
        );
      }
      return;
    }
    await _runDownload(normalized, automatic: automatic);
  }

  Future<void> _runDownload(
    String normalized, {
    required bool automatic,
  }) async {
    final model = _store.modelFor(normalized);
    final partial = await _store.partialBytes(normalized);
    _update(
      normalized,
      state
          .forModel(normalized)
          .copyWith(
            status: AiDictationModelTransferStatus.downloading,
            installed: false,
            receivedBytes: partial,
            totalBytes: model.sizeBytes,
            clearMessage: true,
          ),
      activeModelId: normalized,
    );
    try {
      await _store.download(
        id: normalized,
        onProgress: (progress) {
          if (_disposed) return;
          _update(
            normalized,
            state
                .forModel(normalized)
                .copyWith(
                  status: progress >= 1
                      ? AiDictationModelTransferStatus.verifying
                      : AiDictationModelTransferStatus.downloading,
                  receivedBytes: (progress * model.sizeBytes).round(),
                ),
          );
        },
      );
      if (_disposed) return;
      _update(
        normalized,
        state
            .forModel(normalized)
            .copyWith(
              status: AiDictationModelTransferStatus.idle,
              installed: true,
              receivedBytes: model.sizeBytes,
              clearMessage: true,
            ),
        clearActiveModel: true,
      );
    } on AiDictationDownloadCancelled {
      if (_disposed) return;
      _update(
        normalized,
        state
            .forModel(normalized)
            .copyWith(
              status: AiDictationModelTransferStatus.idle,
              receivedBytes: 0,
              clearMessage: true,
            ),
        clearActiveModel: true,
      );
    } on Object catch (error, stackTrace) {
      _log.warning(
        automatic
            ? 'automatic Whisper model resume failed'
            : 'Whisper model download failed',
        error,
        stackTrace,
      );
      if (_disposed) return;
      final retained = await _store.partialBytes(normalized);
      _update(
        normalized,
        state
            .forModel(normalized)
            .copyWith(
              status: retained > 0
                  ? AiDictationModelTransferStatus.resumable
                  : AiDictationModelTransferStatus.failed,
              receivedBytes: retained,
              message: 'The model download could not finish. Try again.',
            ),
        clearActiveModel: true,
      );
    } finally {
      if (!_disposed && state.activeModelId == null && _queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        unawaited(_runDownload(next, automatic: false));
      }
    }
  }

  Future<void> cancel(String id) async {
    final normalized = AiDictationModelStore.modelForId(id);
    if (_queue.remove(normalized)) {
      await _store.cancelDownload(normalized);
      _update(
        normalized,
        state
            .forModel(normalized)
            .copyWith(
              status: AiDictationModelTransferStatus.idle,
              receivedBytes: 0,
              clearMessage: true,
            ),
      );
      return;
    }
    await _store.cancelDownload(normalized);
  }

  Future<void> remove(String id, {required String selectedModelId}) async {
    final normalized = AiDictationModelStore.modelForId(id);
    if (normalized == AiDictationModelStore.modelForId(selectedModelId)) {
      throw StateError(
        'Select another installed model before removing this one.',
      );
    }
    await _store.remove(normalized);
    await refresh();
  }

  void _update(
    String id,
    AiDictationModelTransfer next, {
    String? activeModelId,
    bool clearActiveModel = false,
  }) {
    if (_disposed) return;
    state = state.copyWith(
      models: <String, AiDictationModelTransfer>{...state.models, id: next},
      activeModelId: activeModelId,
      clearActiveModel: clearActiveModel,
    );
  }
}
