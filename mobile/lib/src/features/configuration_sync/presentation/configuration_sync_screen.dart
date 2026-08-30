import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/configuration/alera_configuration_review.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/configuration_sync/application/configuration_sync_service.dart';
import 'package:alera_mobile/src/features/configuration_sync/application/configuration_sync_controller.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConfigurationSyncScreen extends ConsumerWidget {
  const ConfigurationSyncScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts =
        ref.watch(cloudAccountsControllerProvider).asData?.value ?? [];
    final hosts = ref.watch(availableHostsProvider).asData?.value ?? [];
    final selection = ref.watch(configurationSyncSelectionProvider);
    final selector = ref.read(configurationSyncSelectionProvider.notifier);
    final accountId = accounts.any((s) => s.account.id == selection.accountId)
        ? selection.accountId
        : accounts.firstOrNull?.account.id;
    final accountHosts = hosts
        .where((h) => h.accountId == null || h.accountId == accountId)
        .toList();
    final hostId = accountHosts.any((h) => h.id == selection.hostId)
        ? selection.hostId
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration Sync')),
      body: ListView(
        padding: AleraTokens.pagePadding,
        children: [
          if (accounts.isEmpty)
            const Text(
              'Sign in from Alera Accounts to synchronize configuration.',
            ),
          if (accountId != null) ...[
            DropdownButtonFormField<String>(
              initialValue: accountId,
              decoration: const InputDecoration(labelText: 'Alera Account'),
              items: [
                for (final session in accounts)
                  DropdownMenuItem(
                    value: session.account.id,
                    child: Text(session.account.email),
                  ),
              ],
              onChanged: selector.selectAccount,
            ),
            const SizedBox(height: AleraTokens.space12),
            DropdownButtonFormField<String>(
              key: ValueKey(accountId),
              initialValue: hostId ?? '',
              decoration: const InputDecoration(labelText: 'Target Device'),
              items: [
                const DropdownMenuItem(value: '', child: Text('This Phone')),
                for (final host in accountHosts)
                  DropdownMenuItem(
                    value: host.id,
                    child: Text('Connected Device: ${host.effectiveName}'),
                  ),
              ],
              onChanged: (id) => selector.selectHost(id == '' ? null : id),
            ),
            const SizedBox(height: AleraTokens.space12),
            _SyncTarget(accountId: accountId, hostId: hostId),
          ],
        ],
      ),
    );
  }
}

class _SyncTarget extends ConsumerWidget {
  const _SyncTarget({required this.accountId, required this.hostId});
  final String accountId;
  final String? hostId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serviceProvider = configurationSyncServiceProvider(accountId, hostId);
    return ref
        .watch(serviceProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Column(
            children: [
              Text(error.toString()),
              TextButton(
                onPressed: () => ref.invalidate(serviceProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (service) {
            final provider = configurationSyncControllerProvider(service);
            return ref
                .watch(provider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Column(
                    children: [
                      Text(error.toString()),
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
