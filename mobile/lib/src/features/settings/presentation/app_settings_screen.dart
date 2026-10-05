import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/configuration_sync/presentation/configuration_sync_screen.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/accounts/presentation/accounts_screen.dart';
import 'package:alera_mobile/src/features/diagnostics/presentation/diagnostics_screen.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_settings_screen.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_hosts_settings_screen.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_clipboard_setting_tile.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_keys_settings_screen.dart';
import 'package:flutter/material.dart';

/// App-scoped settings (this phone). Host-portable settings stay under
/// [HostSettingsScreen].
class const AppSettingsScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: AleraTokens.pagePadding,
          children: <Widget>[
            const _SettingsGroup(
              label: 'Sync',
              first: true,
              children: <Widget>[
                _SettingsLink(
                  icon: Icons.sync,
                  title: 'Configuration Sync',
                  subtitle: 'Review, download and upload preferences',
                  destination: ConfigurationSyncScreen(),
                ),
              ],
            ),
            const _SettingsGroup(
              label: 'Account',
              children: <Widget>[
                _SettingsLink(
                  icon: Icons.person_outline,
                  title: 'Alera Accounts',
                  subtitle: 'Cloud identity and notifications',
                  destination: AccountsScreen(),
                ),
              ],
            ),
            const _SettingsGroup(
              label: 'Terminal',
              children: <Widget>[
                _SettingsLink(
                  icon: Icons.keyboard_outlined,
                  title: 'Terminal Quick Keys',
                  subtitle: 'On this phone',
                  destination: TerminalKeysSettingsScreen(),
                ),
                TerminalClipboardSettingTile(),
              ],
            ),
            const _SettingsGroup(
              label: 'AI',
              children: <Widget>[
                _SettingsLink(
                  icon: Icons.data_usage,
                  title: 'Quota Hosts',
                  subtitle: 'Choose which hosts show quotas on Home',
                  destination: QuotaHostsSettingsScreen(),
                ),
                _SettingsLink(
                  icon: Icons.mic_none,
                  title: 'AI Dictation',
                  subtitle: 'On this phone',
                  destination: MobileAiDictationSettingsScreen(),
                ),
              ],
            ),
            const _SettingsGroup(
              label: 'Diagnostics',
              children: <Widget>[
                _SettingsLink(
                  icon: Icons.bug_report_outlined,
                  title: 'Logs And Crash Reports',
                  subtitle: 'On this phone',
                  destination: DiagnosticsScreen(),
                ),
              ],
            ),
            _SettingsGroup(
              label: 'About',
              children: <Widget>[
                Padding(
                  padding: AleraTokens.contentPadding,
                  child: Column(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Text('Alera', style: theme.textTheme.titleMedium),
                      const SizedBox(height: AleraTokens.spaceXs),
                      Text(
                        'Mobile Companion',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                      const SizedBox(height: AleraTokens.spaceSm),
                      Text(
                        'Pair with desktop hosts to manage workspaces, terminals, and agent quotas from this phone.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One settings section: a header and a single card whose rows are split by
/// dividers.
class const _SettingsGroup({
  required final String label,
  required final List<Widget> children,
  final bool first = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraSectionHeader(
          label: label,
          padding: EdgeInsets.only(
            left: AleraTokens.space4,
            top: first ? 0 : AleraTokens.spaceXl,
            bottom: AleraTokens.spaceSm,
          ),
        ),
        Card(
          child: Column(
            children: <Widget>[
              for (final (index, child) in children.indexed) ...<Widget>[
                if (index > 0) const Divider(),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class const _SettingsLink({
  required final IconData icon,
  required final String title,
  required final String subtitle,
  required final Widget destination,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(AleraIcons.chevronRight, size: AleraTokens.space16),
      onTap: () =>
          Navigator.of(context)
              .push<void>(MaterialPageRoute<void>(builder: (_) => destination)),
    );
  }
}
