import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/presentation/pair_host_screen.dart';
import 'package:alera_mobile/src/features/runtime/presentation/host_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HostListScreen extends ConsumerWidget {
  const HostListScreen({super.key});

  Future<void> _pairHost(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const PairHostScreen()),
    );
  }

  Future<void> _removeHost(
    BuildContext context,
    WidgetRef ref,
    PairedHostProfile host,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Host'),
        content: Text(host.displayName),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(pairedHostsControllerProvider.notifier).removeHost(host.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(pairedHostsControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alera'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Pair Host',
            onPressed: () => _pairHost(context),
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (hosts) {
          AsyncData(value: final hostList) when hostList.isEmpty => _EmptyHosts(
            onPairHost: () => _pairHost(context),
          ),
          AsyncData(value: final hostList) => ListView.separated(
            padding: AleraTokens.pagePadding,
            itemBuilder: (context, index) {
              final host = hostList[index];
              return _HostCard(
                host: host,
                onOpen: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HostDashboardScreen(host: host),
                    ),
                  );
                },
                onRemove: () => _removeHost(context, ref, host),
              );
            },
            separatorBuilder: (_, _) =>
                const SizedBox(height: AleraTokens.spaceMd),
            itemCount: hostList.length,
          ),
          AsyncError(:final error) => Center(child: Text(error.toString())),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Pair Host',
        onPressed: () => _pairHost(context),
        child: const Icon(Icons.add_link),
      ),
    );
  }
}

class _EmptyHosts extends StatelessWidget {
  const _EmptyHosts({required this.onPairHost});

  final VoidCallback onPairHost;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.devices_other,
              size: AleraTokens.emptyIcon,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text(
              'No Paired Hosts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            FilledButton.icon(
              onPressed: onPairHost,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Pair Host'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({
    required this.host,
    required this.onOpen,
    required this.onRemove,
  });

  final PairedHostProfile host;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        onTap: onOpen,
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Row(
            children: <Widget>[
              Container(
                width: AleraTokens.iconLg,
                height: AleraTokens.iconLg,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(
                    alpha: AleraTokens.emphasisOverlayAlpha,
                  ),
                  borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                ),
                child: Icon(
                  Icons.computer,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: AleraTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      host.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AleraTokens.spaceXs),
                    Text(
                      host.endpoint,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove Host',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
