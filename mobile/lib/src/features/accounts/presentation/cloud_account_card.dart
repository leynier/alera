import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:flutter/material.dart';

enum CloudAccountAction { refresh, remove }

class CloudAccountCard extends StatelessWidget {
  const CloudAccountCard({
    super.key,
    required this.session,
    required this.hosts,
    required this.onPreferencesChanged,
    required this.onAction,
  });

  final CloudAccountSession session;
  final List<PairedHostProfile> hosts;
  final Future<void> Function(
    String runtimeId,
    RuntimePushPreferences preferences,
  )
  onPreferencesChanged;
  final ValueChanged<CloudAccountAction> onAction;

  @override
  Widget build(BuildContext context) {
    final entries = session.subscriptions.entries.toList(growable: false);
    final active = entries.any((entry) => entry.value.hasEnabledCategory);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        session.account.email,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                          value: CloudAccountAction.refresh,
                          child: Text('Refresh Account'),
                        ),
                        PopupMenuItem<CloudAccountAction>(
                          value: CloudAccountAction.remove,
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
                'No Enrolled Runtimes',
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

class _RuntimeRail extends StatelessWidget {
  const _RuntimeRail({
    required this.entries,
    required this.hosts,
    required this.onPreferencesChanged,
  });

  final List<MapEntry<String, RuntimePushPreferences>> entries;
  final List<PairedHostProfile> hosts;
  final Future<void> Function(
    String runtimeId,
    RuntimePushPreferences preferences,
  )
  onPreferencesChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        AleraTokens.space8,
        AleraTokens.space12,
        AleraTokens.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
    );
  }
}

class _RuntimeNotificationRow extends StatelessWidget {
  const _RuntimeNotificationRow({
    required this.runtimeId,
    required this.host,
    required this.preferences,
    required this.onChanged,
  });

  final String runtimeId;
  final PairedHostProfile? host;
  final RuntimePushPreferences preferences;
  final ValueChanged<RuntimePushPreferences> onChanged;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        host?.effectiveName ?? 'Unpaired Runtime',
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AleraTokens.space2),
                      Text(
                        runtimeId,
                        style: AleraTokens.monoStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
