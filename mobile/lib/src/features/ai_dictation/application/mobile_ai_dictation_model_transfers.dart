import 'dart:async';

import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_model_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_ai_dictation_model_transfers.g.dart';

enum MobileAiModelTransferStatus {
  idle,
  downloading,
  verifying,
  resumable,
  failed,
}

class MobileAiModelTransfer {
  const MobileAiModelTransfer({
    this.status = MobileAiModelTransferStatus.idle,
    this.installed = false,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.message,
  });

  final MobileAiModelTransferStatus status;
  final bool installed;
  final int receivedBytes;
  final int totalBytes;
  final String? message;

  double get progress => totalBytes == 0 ? 0 : receivedBytes / totalBytes;
}

class MobileAiModelTransfersState {
  const MobileAiModelTransfersState(this.models, {this.activeModelId});
  final Map<String, MobileAiModelTransfer> models;
  final String? activeModelId;
  MobileAiModelTransfer forModel(String id) =>
      models[id] ?? const MobileAiModelTransfer();
}

@Riverpod(keepAlive: true)
class MobileAiDictationModelTransfers
    extends _$MobileAiDictationModelTransfers {
  late final MobileAiDictationModelStore _store;

  @override
  MobileAiModelTransfersState build() {
    _store = MobileAiDictationModelStore();
    unawaited(Future<void>.microtask(refresh));
    return MobileAiModelTransfersState(<String, MobileAiModelTransfer>{
      for (final model in MobileAiDictationModelStore.models)
        model.id: MobileAiModelTransfer(totalBytes: model.sizeBytes),
    });
  }

  Future<void> refresh() async {
    final resumable = await _store.resumableModelIds();
    final models = <String, MobileAiModelTransfer>{};
    for (final model in MobileAiDictationModelStore.models) {
      final installed = await _store.isInstalled(model.id);
      final received = installed
          ? model.sizeBytes
          : await _store.partialBytes(model.id);
      models[model.id] = MobileAiModelTransfer(
        installed: installed,
        receivedBytes: received,
        totalBytes: model.sizeBytes,
        status: resumable.contains(model.id)
            ? MobileAiModelTransferStatus.resumable
            : MobileAiModelTransferStatus.idle,
      );
    }
    state = MobileAiModelTransfersState(
      models,
      activeModelId: state.activeModelId,
    );
  }

  Future<void> download(String id) async {
    if (state.activeModelId != null) return;
    _set(
      id,
      MobileAiModelTransfer(
        status: MobileAiModelTransferStatus.downloading,
        totalBytes: _store.modelFor(id).sizeBytes,
        receivedBytes: await _store.partialBytes(id),
      ),
      activeModelId: id,
    );
    try {
      await _store.download(
        id,
        onProgress: (received, total) => _set(
          id,
          MobileAiModelTransfer(
            status: received >= total
                ? MobileAiModelTransferStatus.verifying
                : MobileAiModelTransferStatus.downloading,
            receivedBytes: received,
            totalBytes: total,
          ),
          activeModelId: id,
        ),
      );
      await refresh();
    } on MobileAiModelDownloadCancelled {
      await refresh();
    } on Object catch (error) {
      final received = await _store.partialBytes(id);
      _set(
        id,
        MobileAiModelTransfer(
          status: received > 0
              ? MobileAiModelTransferStatus.resumable
              : MobileAiModelTransferStatus.failed,
          receivedBytes: received,
          totalBytes: _store.modelFor(id).sizeBytes,
          message: 'The model download could not finish: $error',
        ),
      );
    } finally {
      state = MobileAiModelTransfersState(state.models);
    }
  }

  Future<void> cancel(String id) async {
    await _store.cancel(id);
    await refresh();
  }

  Future<void> remove(String id, {required String selectedModelId}) async {
    if (id == selectedModelId) {
      throw StateError(
        'Select another installed model before removing this one.',
      );
    }
    await _store.remove(id);
    await refresh();
  }

  Future<String> modelPath(String id) => _store.modelPath(id);
  Future<bool> isInstalled(String id) => _store.isInstalled(id);

  void _set(
    String id,
    MobileAiModelTransfer transfer, {
    String? activeModelId,
  }) {
    state = MobileAiModelTransfersState(<String, MobileAiModelTransfer>{
      ...state.models,
      id: transfer,
    }, activeModelId: activeModelId);
  }
}
