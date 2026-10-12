import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/inbox/presentation/load_more_button.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_detail_screen.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

MobileRunBoardProvider runBoardProviderFor(
  String hostId,
  RunBucket bucket,
  MobileRunListState filters,
) => mobileRunBoardProvider(
  hostId,
  bucket: bucket,
  search: filters.search.trim().isEmpty ? null : filters.search.trim(),
  workspaceId: filters.workspaceId,
);

/// Runs of the host in Attention, Active and History groups. The Runs part
/// of Activity. Each group renders from its last page, so a reconnect keeps
/// the list and its scroll offset.
class const RunsSectionBody({super.key, required final String hostId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(mobileRunListControllerProvider(hostId));
    final providers = <RunBucket, MobileRunBoardProvider>{
      for (final bucket in filters.buckets)
        bucket: runBoardProviderFor(hostId, bucket, filters),
    };
    final pages = <RunBucket, AsyncValue<RunBoardPage>>{
      for (final entry in providers.entries) entry.key: ref.watch(entry.value),
    };
    final loaded = pages.values.where((page) => page.hasValue).toList();
    if (loaded.isEmpty) {
      final failed = pages.values.where((page) => page.hasError).firstOrNull;
      if (failed == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return _RunsError(
        error: failed.error!,
        onRetry: () {
          for (final provider in providers.values) {
            ref.invalidate(provider);
          }
        },
      );
    }
    final runs = <RunSummary>[for (final page in loaded) ...page.value!.items];
    final offline = pages.values.any((page) => page.hasError);
    return RefreshIndicator(
      onRefresh: () => Future.wait(<Future<RunBoardPage>>[
        for (final provider in providers.values) ref.refresh(provider.future),
      ]),
      child: ListView(
        padding: AleraTokens.pagePadding,
        children: <Widget>[
          if (offline)
            const Padding(
              padding: EdgeInsets.only(bottom: AleraTokens.spaceSm),
              child: AleraNotice(
                message: 'Offline. Showing the last runs from this host; actions are unavailable until it reconnects.',
              ),
            ),
          if (filters.isFiltered)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: ref
                    .read(mobileRunListControllerProvider(hostId).notifier)
                    .clear,
                icon: const Icon(AleraIcons.close),
                label: const Text('Clear Filters'),
              ),
            ),
          if (runs.isEmpty)
            AleraEmptyState(
              icon: AleraIcons.workspaceChildren,
              message: filters.isFiltered
                  ? 'No runs match these filters.'
                  : 'No runs yet. Start one with New Run.',
            )
          else
            for (final entry in pages.entries)
              if (entry.value.value case final page?
                  when page.items.isNotEmpty) ...<Widget>[
                AleraSectionHeader(
                  label: entry.key.label,
                  trailing: Text(
                    '${page.counts.countFor(entry.key)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                for (final run in page.items)
                  RunCard(
                    run: run,
                    // A run that names its due gate opens on it.
                    onOpen: () => unawaited(
                      openRun(
                        context,
                        hostId,
                        run.id,
                        gateId: run.pendingGates.firstOrNull?.id,
                      ),
                    ),
                  ),
                if (page.nextCursor != null)
                  LoadMoreButton(
                    label: 'Load More Runs',
                    onLoad: ref.read(providers[entry.key]!.notifier).loadMore,
                  ),
              ],
          const SizedBox(height: AleraTokens.spaceXxl * 2),
        ],
      ),
    );
  }
}

class const _RunsError({
  required final Object error,
  required final VoidCallback onRetry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => error is RunsUpdateRequired
      ? const AleraEmptyState(
          icon: AleraIcons.systemUpdate,
          title: 'Update Required',
          message: RunsUpdateRequired.message,
        )
      : AleraEmptyState(
          icon: AleraIcons.loadFailed,
          title: 'Runs Unavailable',
          message: 'The host could not load its runs.',
          detail: runErrorMessage(error),
          action: TextButton(onPressed: onRetry, child: const Text('Retry')),
        );
}

/// One run: objective, status, what needs a person, and where it runs.
class const RunCard({
  super.key,
  required final RunSummary run,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = runStatusLabel(run);
    final attention = runAttentionSummary(run);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final age = runAgeLabel(
      run.lastActivityAt ?? run.createdAt,
      DateTime.now().toUtc(),
    );
    return Card(
      key: ValueKey<String>('run-card-${run.id}'),
      margin: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Text(
                run.objective.isEmpty ? 'Untitled Run' : run.objective,
                maxLines: 2,
                overflow: .ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AleraTokens.space8),
              Row(
                children: <Widget>[
                  AleraBadge(label: status.label, tone: status.tone),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      attention ?? runProgressLabel(run),
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AleraTokens.space4),
              Text(
                <String>[
                  run.workspaceLabel,
                  if (age.isNotEmpty) age,
                ].join(' · '),
                maxLines: 1,
                overflow: .ellipsis,
                style: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
