import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/quotas/application/quota_host_visibility_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuotaHostsSettingsScreen extends ConsumerWidget {
  const QuotaHostsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(availableHostsProvider);
    final visibility = ref.watch(quotaHostVisibilityControllerProvider);
    final hostList = hosts.value;
    final hidden = visibility.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Quota Hosts')),
      body: SafeArea(
        child: hosts.hasError || visibility.hasError
            ? AleraEmptyState(
                message: 'Could not load quota hosts.',
                action: TextButton(
                  onPressed: () {
                    ref.invalidate(availableHostsProvider);
                    ref.invalidate(quotaHostVisibilityControllerProvider);
                  },
                  child: const Text('Retry'),
                ),
              )
            : hostList == null || hidden == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: AleraTokens.pagePadding,
                children: <Widget>[
                  Text(
                    'Choose which hosts show quotas on Home. If hosts share '
                    'the same accounts, select just one to avoid duplicates.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AleraTokens.spaceSm),
                  Text(
                    'Saved on this phone. Individual host quotas and desktop '
                    'settings are unchanged. New hosts are shown by default.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AleraTokens.spaceLg),
                  if (hostList.isEmpty)
                    const AleraEmptyState(
                      message: 'Pair a host or sign in to choose quota hosts.',
                    ),
                  for (final host in hostList) ...<Widget>[
                    Card(
                      child: SwitchListTile(
                        title: Text(host.effectiveName),
                        subtitle: Text(host.endpoint),
                        value: !hidden.contains(host.runtimeId),
                        onChanged: (visible) => _setHostVisible(
                          context,
                          ref,
                          host.runtimeId,
                          visible,
                        ),
                      ),
                    ),
                    const SizedBox(height: AleraTokens.spaceSm),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _setHostVisible(
    BuildContext context,
    WidgetRef ref,
    String runtimeId,
    bool visible,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(quotaHostVisibilityControllerProvider.notifier)
          .setHostVisible(runtimeId, visible);
    } on Object {
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save quota hosts. Try again.')),
      );
    }
  }
}
