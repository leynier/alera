import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class const PullRequestPanel({
  super.key,
  required final String hostId,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pullRequestControllerProvider(hostId, workspaceId));
    return switch (state) {
      AsyncData(value: final snapshot) => _Body(snapshot: snapshot),
      AsyncError(:final error) => AleraEmptyState(
        icon: AleraIcons.gitPullRequest,
        message: error.toString(),
        action: FilledButton(
          onPressed: () => ref
              .read(pullRequestControllerProvider(hostId, workspaceId).notifier)
              .reload(),
          child: const Text('Retry'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class const _Body({required final MobilePullRequestSnapshot snapshot})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final review = snapshot.review;
    if (review == null) {
      return AleraEmptyState(
        icon: AleraIcons.gitPullRequest,
        title: snapshot.identity?.label ?? snapshot.branch ?? 'Pull request',
        message:
            snapshot.unavailableReason ??
            'No pull request is available for this workspace.',
      );
    }
    return ListView(
      padding: AleraTokens.contentPadding,
      children: <Widget>[
        if (snapshot.identity?.label != null)
          Text(
            snapshot.identity!.label!,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        Text(review.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AleraTokens.space8),
        Text(
          '#${review.number} · ${review.isDraft ? 'Draft' : review.state}'
          '${review.author == null ? '' : ' · ${review.author}'}',
        ),
        if (review.baseRefName != null &&
            review.headRefName != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Text('${review.headRefName} into ${review.baseRefName}'),
        ],
        const SizedBox(height: AleraTokens.space12),
        Text(
          'Comments are read-only. Reply, edit, and merge stay on desktop.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (review.url.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space16),
          FilledButton.icon(
            onPressed: () => _open(review.url),
            icon: const Icon(AleraIcons.external),
            label: const Text('Open In Browser'),
          ),
        ],
        const SizedBox(height: AleraTokens.space24),
        Text('Checks', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.space8),
        if (review.checks.isEmpty)
          const Text('No checks were returned for this pull request.')
        else
          for (final check in review.checks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                check.bucket == 'pass' ? AleraIcons.success : AleraIcons.review,
              ),
              title: Text(check.name),
              subtitle: Text(check.bucket.isEmpty ? check.state : check.bucket),
              onTap: check.url == null ? null : () => _open(check.url!),
            ),
        const SizedBox(height: AleraTokens.space16),
        Text('Comments', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.space8),
        if (review.comments.isEmpty)
          const Text('No conversation comments yet.')
        else
          for (final comment in review.comments)
            Card(
              child: Padding(
                padding: AleraTokens.contentPadding,
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      comment.author ?? 'Comment',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AleraTokens.space8),
                    Text(comment.body),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _open(String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      return;
    }
    await launchUrl(parsed, mode: .externalApplication);
  }
}
