import 'package:alera/src/design_system/configuration/alera_configuration_review.dart';
import 'package:alera/src/features/configuration_sync/application/configuration_sync_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConfigurationSyncPane extends ConsumerWidget {
  const ConfigurationSyncPane({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(configurationSyncServiceProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(e.toString()),
          data: (service) {
            final provider = configurationSyncControllerProvider(service);
            return ref
                .watch(provider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Column(
                    children: [
                      Text(e.toString()),
                      TextButton(
                        onPressed: () => ref.invalidate(provider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                  data: (state) {
                    final controller = ref.read(provider.notifier);
                    return AleraConfigurationReview(
                      target: service.target.label,
                      state: state,
                      onRefresh: controller.refresh,
                      onHistory: controller.loadHistory,
                      onRestore: (revision) =>
                          controller.refresh(revision: revision),
                      onChoice: controller.choose,
                      onRename: controller.rename,
                      onChooseAll: controller.chooseAll,
                      onApply: (upload) => controller.apply(upload: upload),
                      onRetry: controller.retry,
                    );
                  },
                );
          },
        );
  }
}
