part of 'mobile_ai_dictation_settings_screen.dart';

class const _LocalModelList() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref
        .watch(mobileAiDictationSettingsControllerProvider)
        .value;
    final transfers = ref.watch(mobileAiDictationModelTransfersProvider);
    final transferController = ref.read(
      mobileAiDictationModelTransfersProvider.notifier,
    );
    if (settings == null) return const SizedBox.shrink();
    return Column(
      children: <Widget>[
        for (final (index, model) in MobileAiDictationModelStore.models.indexed)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == MobileAiDictationModelStore.models.length - 1
                  ? 0
                  : AleraTokens.spaceSm,
            ),
            child: _ModelTile(
              model: model,
              transfer: transfers.forModel(model.id),
              selected: settings.localModelId == model.id,
              busy: transfers.activeModelId != null,
              onDownload: () => transferController.download(model.id),
              onCancel: () => transferController.cancel(model.id),
              onSelect: () => ref
                  .read(mobileAiDictationSettingsControllerProvider.notifier)
                  .save(settings.copyWith(localModelId: model.id)),
              onRemove: () => transferController.remove(
                model.id,
                selectedModelId: settings.localModelId,
              ),
            ),
          ),
      ],
    );
  }
}

class const _ModelTile({
  required final MobileAiDictationModel model,
  required final MobileAiModelTransfer transfer,
  required final bool selected,
  required final bool busy,
  required final Future<void> Function() onDownload,
  required final Future<void> Function() onCancel,
  required final Future<void> Function() onSelect,
  required final Future<void> Function() onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloading =
        transfer.status == MobileAiModelTransferStatus.downloading ||
        transfer.status == MobileAiModelTransferStatus.verifying;
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(model.label, style: theme.textTheme.titleSmall),
                ),
                if (selected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space8,
                      vertical: AleraTokens.space4,
                    ),
                    decoration: BoxDecoration(
                      color: AleraTokens.accentSubtle,
                      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                      border: Border.all(color: AleraTokens.border),
                    ),
                    child: Text(
                      'Selected',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AleraTokens.foreground,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              _modelStatus(model, transfer, selected),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            if (downloading) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              LinearProgressIndicator(
                value: transfer.status == MobileAiModelTransferStatus.verifying
                    ? null
                    : transfer.progress,
              ),
            ],
            const SizedBox(height: AleraTokens.space8),
            Wrap(
              alignment: .end,
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: <Widget>[
                if (downloading)
                  OutlinedButton(
                    onPressed: () => unawaited(onCancel()),
                    child: const Text('Cancel Download'),
                  )
                else if (!transfer.installed)
                  FilledButton(
                    onPressed: busy ? null : () => unawaited(onDownload()),
                    child: Text(
                      transfer.status == MobileAiModelTransferStatus.resumable
                          ? 'Resume'
                          : 'Download',
                    ),
                  )
                else ...<Widget>[
                  OutlinedButton(
                    onPressed: selected ? null : () => unawaited(onRemove()),
                    child: const Text('Remove Model'),
                  ),
                  FilledButton(
                    onPressed: selected ? null : () => unawaited(onSelect()),
                    child: Text(selected ? 'Selected' : 'Use Model'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _modelStatus(
  MobileAiDictationModel model,
  MobileAiModelTransfer transfer,
  bool selected,
) => switch (transfer.status) {
  MobileAiModelTransferStatus.downloading =>
    '${_formatBytes(transfer.receivedBytes)} of ${_formatBytes(transfer.totalBytes)}',
  MobileAiModelTransferStatus.verifying => 'Verifying downloaded model...',
  MobileAiModelTransferStatus.resumable =>
    'Download interrupted at ${_formatBytes(transfer.receivedBytes)}.',
  MobileAiModelTransferStatus.failed =>
    transfer.message ?? 'The model download failed.',
  MobileAiModelTransferStatus.idle when transfer.installed =>
    selected ? 'Installed and selected.' : 'Installed on this device.',
  MobileAiModelTransferStatus.idle =>
    '${model.description} Download size ${_formatBytes(model.totalBytes)}.',
};

String _formatBytes(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
