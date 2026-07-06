import 'package:flutter/material.dart';

import '../models.dart';
import '../storage/host_repository.dart';
import '../theme/alera_tokens.dart';
import 'host_dashboard_screen.dart';
import 'pair_host_screen.dart';

class HostListScreen extends StatefulWidget {
  const HostListScreen({super.key, required this.hostRepository});

  final HostRepository hostRepository;

  @override
  State<HostListScreen> createState() => _HostListScreenState();
}

class _HostListScreenState extends State<HostListScreen> {
  late Future<List<PairedHostProfile>> _hostsFuture;

  @override
  void initState() {
    super.initState();
    _hostsFuture = widget.hostRepository.loadHosts();
  }

  void _refresh() {
    setState(() {
      _hostsFuture = widget.hostRepository.loadHosts();
    });
  }

  Future<void> _pairHost() async {
    final paired = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PairHostScreen(hostRepository: widget.hostRepository),
      ),
    );
    if (paired == true) {
      _refresh();
    }
  }

  Future<void> _removeHost(PairedHostProfile host) async {
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
    await widget.hostRepository.removeHost(host.id);
    if (mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alera Mobile'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Pair Host',
            onPressed: _pairHost,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<PairedHostProfile>>(
          future: _hostsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final hosts = snapshot.data ?? const <PairedHostProfile>[];
            if (hosts.isEmpty) {
              return _EmptyHosts(onPairHost: _pairHost);
            }
            return ListView.separated(
              padding: AleraTokens.pagePadding,
              itemBuilder: (context, index) {
                final host = hosts[index];
                return _HostCard(
                  host: host,
                  onOpen: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HostDashboardScreen(
                          host: host,
                          hostRepository: widget.hostRepository,
                        ),
                      ),
                    );
                  },
                  onRemove: () => _removeHost(host),
                );
              },
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AleraTokens.spaceMd),
              itemCount: hosts.length,
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Pair Host',
        onPressed: _pairHost,
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
