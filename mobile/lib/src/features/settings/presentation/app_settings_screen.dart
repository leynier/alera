import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_keys_settings_screen.dart';
import 'package:flutter/material.dart';

/// App-scoped settings (this phone). Host-portable settings stay under
/// [HostSettingsScreen].
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: AleraTokens.pagePadding,
          children: <Widget>[
            Text('Terminal', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AleraTokens.spaceSm),
            Card(
              child: ListTile(
                leading: const Icon(Icons.keyboard_outlined),
                title: const Text('Terminal Quick Keys'),
                subtitle: const Text('On This Phone'),
                trailing: const Icon(AleraIcons.chevronRight, size: 16),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const TerminalKeysSettingsScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.spaceXl),
            Text('About', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AleraTokens.spaceSm),
            Card(
              child: Padding(
                padding: AleraTokens.contentPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Alera',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AleraTokens.spaceXs),
                    Text(
                      'Mobile Companion',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.spaceSm),
                    Text(
                      'Pair With Desktop Hosts To Manage Workspaces, Terminals, And Agent Quotas From This Phone.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
