import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/voice/application/mobile_voice_session_controller.dart';
import 'package:alera_mobile/src/features/voice/presentation/mobile_voice_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const MobileVoiceScreen({super.key, required this.host})
    extends ConsumerWidget {
  final PairedHostProfile host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(mobileVoiceSessionControllerProvider(host.id));
    final notifier = ref.read(
      mobileVoiceSessionControllerProvider(host.id).notifier,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Voice settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => MobileVoiceSettingsScreen(host: host),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: AleraTokens.pagePadding,
        children: <Widget>[
          Text(
            'Speech is I/O. The desktop home CLI thinks and delegates.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AleraTokens.spaceLg),
          Text('Home agent: ${status.phase}'),
          if (status.queuedTurnCount > 0 ||
              status.queuedSpeakCount > 0) ...<Widget>[
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              'Queued: ${status.queuedTurnCount} turns, ${status.queuedSpeakCount} spoken replies.',
            ),
          ],
          if (status.lastSpoken != null) ...<Widget>[
            const SizedBox(height: AleraTokens.spaceSm),
            Text(status.lastSpoken!),
          ],
          if (status.lastError != null) ...<Widget>[
            const SizedBox(height: AleraTokens.spaceSm),
            SelectableText(
              status.lastError!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AleraTokens.spaceLg),
          FilledButton(
            onPressed: status.busy ? null : notifier.toggle,
            child: Text(status.active ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}
