import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:alera_mobile/src/features/accounts/presentation/cloud_account_card.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/push_notifications/application/push_coordinator.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const AccountsScreen({super.key}) extends ConsumerWidget {
  Future<void> _addAccount(BuildContext context, WidgetRef ref) async {
    final hosts = await ref.read(pairedHostsControllerProvider.future);
    if (!context.mounted) {
      return;
    }
    if (hosts.isEmpty) {
      _showMessage(context, 'Pair a host before adding its account');
      return;
    }
    final host = hosts.length == 1
        ? hosts.single
        : await _selectHost(context, hosts);
    if (host == null || !context.mounted) {
      return;
    }
    final provider = hostConnectionControllerProvider(host.id);
    final connection = ref.listenManual(provider, (_, _) {});
    try {
      final client = await ref.read(provider.future);
      final code = await client.createCloudEnrollment();
      await ref
          .read(cloudAccountsControllerProvider.notifier)
          .redeemEnrollment(code);
      await ref.read(pushCoordinatorProvider.notifier).reconcile();
      await client.refreshCloudSubscriptions();
      if (context.mounted) {
        _showMessage(context, 'Account added');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(context, error.toString());
      }
    } finally {
      connection.close();
    }
  }

  Future<void> _signInDirect(
    BuildContext context,
    WidgetRef ref,
    String provider,
  ) async {
    try {
      await ref.read(cloudAccountsControllerProvider.notifier).signIn(provider);
      await ref.read(pushCoordinatorProvider.notifier).reconcile();
      if (context.mounted) {
        _showMessage(context, 'Account added');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(context, error.toString());
      }
    }
  }

  Future<PairedHostProfile?> _selectHost(
    BuildContext context,
    List<PairedHostProfile> hosts,
  ) {
    return showDialog<PairedHostProfile>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose A Paired Host'),
        children: <Widget>[
          for (final host in hosts)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(host),
              child: Text(host.effectiveName),
            ),
        ],
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _removeAccount(
    BuildContext context,
    WidgetRef ref,
    CloudAccountSession session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Remove Account',
        message:
            'Remove ${session.account.email} and its push subscriptions from this phone?',
        confirmLabel: 'Remove',
        destructive: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(cloudAccountsControllerProvider.notifier)
          .removeFromThisPhone(session.account.id);
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(context, error.toString());
      }
      return;
    }
    for (final runtimeId in session.subscriptions.keys) {
      await _refreshPairedRuntime(ref, runtimeId);
    }
  }

  Future<void> _refreshAccount(
    BuildContext context,
    WidgetRef ref,
    String accountId,
  ) async {
    try {
      await ref
          .read(cloudAccountsControllerProvider.notifier)
          .refreshAccount(accountId);
      if (context.mounted) {
        _showMessage(context, 'Account refreshed');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showMessage(context, error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(cloudAccountsControllerProvider);
    final hosts = ref.watch(pairedHostsControllerProvider).value ?? const [];
    final coordination = ref.watch(pushCoordinatorProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: SafeArea(
        child: switch (accounts) {
          AsyncData(value: final sessions) => ListView(
            padding: AleraTokens.pagePadding,
            children: <Widget>[
              _PushStateBanner(state: coordination.value),
              const SizedBox(height: AleraTokens.space16),
              const AleraSectionHeader(label: 'Alera Accounts'),
              if (sessions.isEmpty)
                AleraEmptyState(
                  title: 'No accounts',
                  message: 'Sign in directly or add an account from a paired runtime.',
                  icon: Icons.person_add_alt_1_outlined,
                  action: Column(
                    mainAxisSize: .min,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: () => _signInDirect(context, ref, 'google'),
                        icon: const Icon(Icons.login),
                        label: const Text('Sign In With Google'),
                      ),
                      const SizedBox(height: AleraTokens.space8),
                      OutlinedButton.icon(
                        onPressed: () => _signInDirect(context, ref, 'github'),
                        icon: const Icon(Icons.code),
                        label: const Text('Sign In With GitHub'),
                      ),
                      const SizedBox(height: AleraTokens.space8),
                      TextButton.icon(
                        onPressed: () => _addAccount(context, ref),
                        icon: const Icon(Icons.add_link),
                        label: const Text('Add From Paired Runtime'),
                      ),
                    ],
                  ),
                )
              else
                for (
                  var index = 0;
                  index < sessions.length;
                  index++
                ) ...<Widget>[
                  CloudAccountCard(
                    session: sessions[index],
                    hosts: hosts,
                    onPreferencesChanged: (runtimeId, preferences) =>
                        _updatePreferences(
                          ref,
                          sessions[index],
                          runtimeId,
                          preferences,
                        ),
                    onAction: (action) {
                      switch (action) {
                        case CloudAccountAction.refresh:
                          unawaited(
                            _refreshAccount(
                              context,
                              ref,
                              sessions[index].account.id,
                            ),
                          );
                        case CloudAccountAction.remove:
                          unawaited(
                            _removeAccount(context, ref, sessions[index]),
                          );
                      }
                    },
                  ),
                  if (index < sessions.length - 1)
                    const SizedBox(height: AleraTokens.space12),
                ],
              if (sessions.isNotEmpty) ...<Widget>[
                const SizedBox(height: AleraTokens.space16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _signInDirect(context, ref, 'google'),
                        child: const Text('Sign In With Google'),
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _signInDirect(context, ref, 'github'),
                        child: const Text('Sign In With GitHub'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AleraTokens.space8),
                OutlinedButton.icon(
                  onPressed: () => _addAccount(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Another Account'),
                ),
              ],
            ],
          ),
          AsyncError(:final error) => AleraEmptyState(
            title: 'Accounts unavailable',
            message: error.toString(),
            icon: Icons.cloud_off_outlined,
            action: FilledButton(
              onPressed: () {
                ref.invalidate(cloudAccountsControllerProvider);
              },
              child: const Text('Retry'),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Future<void> _updatePreferences(
    WidgetRef ref,
    CloudAccountSession session,
    String runtimeId,
    RuntimePushPreferences preferences,
  ) async {
    await ref
        .read(cloudAccountsControllerProvider.notifier)
        .updateRuntimePreferences(
          accountId: session.account.id,
          runtimeId: runtimeId,
          preferences: preferences,
        );
    await ref.read(pushCoordinatorProvider.notifier).reconcile();
    await _refreshPairedRuntime(ref, runtimeId);
  }

  Future<void> _refreshPairedRuntime(WidgetRef ref, String runtimeId) async {
    final hosts = await ref.read(pairedHostsControllerProvider.future);
    final host = hosts.where((host) => host.runtimeId == runtimeId).firstOrNull;
    if (host == null) {
      return;
    }
    final provider = hostConnectionControllerProvider(host.id);
    final connection = ref.listenManual(provider, (_, _) {});
    try {
      final client = await ref.read(provider.future);
      await client.refreshCloudSubscriptions();
    } on Object {
      // Cloud already owns the subscription change. The runtime performs the
      // same authoritative refresh when it next starts.
    } finally {
      connection.close();
    }
  }
}

class const _PushStateBanner({required final PushCoordinationState? state})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final status = state?.status ?? PushCoordinationStatus.syncing;
    final (label, color, icon) = switch (status) {
      PushCoordinationStatus.ready => (
        'Push ready',
        AleraTokens.success,
        Icons.notifications_active_outlined,
      ),
      PushCoordinationStatus.idle => (
        'No active subscriptions',
        AleraTokens.foregroundMuted,
        Icons.notifications_none_outlined,
      ),
      PushCoordinationStatus.permissionDenied => (
        'Notification permission is off',
        AleraTokens.warning,
        Icons.notifications_off_outlined,
      ),
      PushCoordinationStatus.unavailable => (
        'Firebase configuration is missing',
        AleraTokens.warning,
        Icons.cloud_off_outlined,
      ),
      PushCoordinationStatus.error => (
        state?.detail ?? 'Push is unavailable',
        AleraTokens.error,
        Icons.error_outline,
      ),
      PushCoordinationStatus.syncing => (
        'Syncing push settings',
        AleraTokens.info,
        Icons.sync,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space8,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color, size: AleraTokens.space20),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
