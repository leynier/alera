import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_job_card.dart';
import 'package:alera_mobile/src/features/workbench/application/background_operations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const BackgroundOperationCards({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(backgroundOperationsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final job in jobs)
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space8),
            child: AleraJobCard(
              title: job.title,
              status: job.error == null ? .running : .failed,
              phase: job.error == null ? 'You can keep using the app.' : null,
              error: job.error,
              onRetry: job.restore == null
                  ? null
                  : () {
                      ref
                          .read(backgroundOperationsProvider.notifier)
                          .dismiss(job.id);
                      job.restore!();
                    },
              onDismiss: job.error == null
                  ? null
                  : () => ref
                        .read(backgroundOperationsProvider.notifier)
                        .dismiss(job.id),
            ),
          ),
      ],
    );
  }
}
