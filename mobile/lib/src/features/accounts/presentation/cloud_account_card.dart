import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:flutter/material.dart';

enum CloudAccountAction { refresh, remove }

class const CloudAccountCard({
  super.key,
  required final CloudAccountSession session,
  required final List<PairedHostProfile> hosts,
  required final Future<void> Function(
    String runtimeId,
    RuntimePushPreferences preferences,
  )
  onPreferencesChanged,
  required final ValueChanged<CloudAccountAction> onAction,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final entries = session.subscriptions.entries.toList(growable: false);
    final active = entries.any((entry) => entry.value.hasEnabledCategory);
    return Card(
      clipBehavior: .antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AleraTokens.space16,
              AleraTokens.space12,
              AleraTokens.space8,
              AleraTokens.space12,
            ),
            child: Row(
              children: <Widget>[
                AleraStatusDot(active: active),
                const SizedBox(width: AleraTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Text(
                        session.account.email,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                      const SizedBox(height: AleraTokens.space4),
                      Wrap(
                        spacing: AleraTokens.space4,
                        runSpacing: AleraTokens.space4,
                        children: <Widget>[
                          for (final provider in session.account.providers)
                            AleraBadge(label: _providerLabel(provider)),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<CloudAccountAction>(
                  onSelected: onAction,
                  itemBuilder: (_) =>
                      const <PopupMenuEntry<CloudAccountAction>>[
                        PopupMenuItem<CloudAccountAction>(
                          value: .refresh,
                          child: Text('Refresh Account'),
                        ),
                        PopupMenuItem<CloudAccountAction>(
                          value: .remove,
                          child: Text('Remove From This Phone'),
                        ),
                      ],
                ),
              ],
            ),
          ),
          const Divider(),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space16),
              child: Text(
                'No enrolled runtimes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            _RuntimeRail(
              entries: entries,
              hosts: hosts,
              onPreferencesChanged: onPreferencesChanged,
            ),
        ],
      ),
    );
  }

  String _providerLabel(String value) {
    return switch (value.toLowerCase()) {
      'github' => 'GitHub',
      'google' => 'Google',
      _ => value,
    };
  }
}

class const _RuntimeRail({
  required final List<MapEntry<String, RuntimePushPreferences>> entries,
  required final List<PairedHostProfile> hosts,
  required final Future<void> Function(
    String runtimeId,
    RuntimePushPreferences preferences,
  )
  onPreferencesChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        AleraTokens.space8,
        AleraTokens.space12,
        AleraTokens.space12,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            SizedBox(
              width: AleraTokens.space16,
              child: Stack(
                alignment: Alignment.topCenter,
                children: <Widget>[
                  Positioned.fill(
                    left: AleraTokens.space6,
                    right: AleraTokens.space8,
                    child: ColoredBox(color: AleraTokens.border),
                  ),
                  for (var index = 0; index < entries.length; index++)
                    Positioned(
                      top:
                          index *
                              (AleraTokens.minTapTarget + AleraTokens.space32) +
                          AleraTokens.space16,
                      child: AleraStatusDot(
                        active: entries[index].value.hasEnabledCategory,
                        size: AleraTokens.space8,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Column(
                children: <Widget>[
                  for (
                    var index = 0;
                    index < entries.length;
                    index++
                  ) ...<Widget>[
                    _RuntimeNotificationRow(
                      runtimeId: entries[index].key,
                      host: hosts
                          .where((host) => host.runtimeId == entries[index].key)
                          .firstOrNull,
                      preferences: entries[index].value,
                      onChanged: (preferences) => unawaited(
                        onPreferencesChanged(entries[index].key, preferences),
                      ),
                    ),
                    if (index < entries.length - 1)
                      const SizedBox(height: AleraTokens.space8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _RuntimeNotificationRow({
  required final String runtimeId,
  required final PairedHostProfile? host,
  required final RuntimePushPreferences preferences,
  required final ValueChanged<RuntimePushPreferences> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Text(
                        host?.effectiveName ?? 'Unpaired runtime',
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                      const SizedBox(height: AleraTokens.space2),
                      Text(
                        runtimeId,
                        style: AleraTokens.monoStyle,
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: preferences.enabled,
                  onChanged: (value) {
                    onChanged(preferences.copyWith(enabled: value));
                  },
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space8),
            Wrap(
              spacing: AleraTokens.space6,
              runSpacing: AleraTokens.space6,
              children: <Widget>[
                FilterChip(
                  label: const Text('Attention'),
                  selected: preferences.attention,
                  onSelected: preferences.enabled
                      ? (value) {
                          onChanged(preferences.copyWith(attention: value));
                        }
                      : null,
                ),
                FilterChip(
                  label: const Text('Done'),
                  selected: preferences.done,
                  onSelected: preferences.enabled
                      ? (value) {
                          onChanged(preferences.copyWith(done: value));
                        }
                      : null,
                ),
                FilterChip(
                  label: const Text('Terminal Exit'),
                  selected: preferences.terminalExit,
                  onSelected: preferences.enabled
                      ? (value) {
                          onChanged(preferences.copyWith(terminalExit: value));
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
