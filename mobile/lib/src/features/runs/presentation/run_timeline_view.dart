import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/inbox/presentation/load_more_button.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:alera_mobile/src/features/runs/domain/run_timeline_models.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_status.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_timeline_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What happened in a run and what its agents told each other, newest first.
class const RunTimelineView({
  super.key,
  required final String hostId,
  required final String runId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = mobileRunTimelineProvider(hostId, runId);
    final timeline = ref.watch(provider);
    return switch (timeline) {
      AsyncValue(value: final RunTimelinePage page) => RefreshIndicator(
        onRefresh: () => ref.refresh(provider.future),
        child: page.items.isEmpty
            ? ListView(
                children: const <Widget>[
                  AleraEmptyState(
                    icon: AleraIcons.workspaceChildren,
                    message: 'Nothing has happened in this run yet.',
                  ),
                ],
              )
            : ListView(
                padding: AleraTokens.pagePadding,
                children: <Widget>[
                  for (final entry in page.items)
                    RunTimelineEntryRow(entry: entry),
                  if (page.nextCursor != null)
                    LoadMoreButton(
                      label: 'Load Older Events',
                      onLoad: ref.read(provider.notifier).loadMore,
                    ),
                ],
              ),
      ),
      AsyncValue(hasError: true, :final error) => AleraEmptyState(
        icon: AleraIcons.loadFailed,
        title: 'Timeline Unavailable',
        message: runErrorMessage(error!),
        action: TextButton(
          onPressed: () => ref.invalidate(provider),
          child: const Text('Retry'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// One event (summary and actor) or one message (sender, recipient, body).
class const RunTimelineEntryRow({
  super.key,
  required final RunTimelineEntry entry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final age = runAgeLabel(entry.createdAt, DateTime.now().toUtc());
    final heading = entry.carriesMessage
        ? '${entry.from ?? 'agent'} → ${entry.to ?? 'agent'}'
        : (entry.summary.isEmpty ? runEventLabel(entry.kind) : entry.summary);
    final actor = entry.actorKind == null
        ? null
        : <String>[entry.actorKind!, ?entry.actorId].join(':');
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space2),
            child: Icon(
              entry.carriesMessage ? AleraIcons.comment : AleraIcons.circle,
              size: AleraTokens.iconSm,
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Text(heading, style: theme.textTheme.bodyMedium),
                if (entry.carriesMessage && (entry.body ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AleraTokens.space2),
                    child: SelectableText(
                      entry.truncated ? '${entry.body}…' : entry.body!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                Text(
                  <String>[
                    entry.isMessage
                        ? runMessageTypeLabel(entry.messageType)
                        : runEventLabel(entry.kind),
                    ?actor,
                    if (age.isNotEmpty) age,
                  ].join(' · '),
                  style: muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
