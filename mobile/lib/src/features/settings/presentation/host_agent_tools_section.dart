import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/settings/application/host_tools_controllers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HostAgentToolsSection extends ConsumerWidget {
  const HostAgentToolsSection({super.key, required this.hostId});

  final String hostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cli = ref.watch(cliRegistrationControllerProvider(hostId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Host Tools', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.spaceSm),
        Card(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.terminal_outlined),
                    const SizedBox(width: AleraTokens.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('Alera CLI Command'),
                          Text(
                            cli.value?.detail ??
                                (cli.hasError
                                    ? cli.error.toString()
                                    : 'Checking registration'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AleraTokens.foregroundMuted),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: cli.isLoading
                          ? null
                          : ref
                                .read(
                                  cliRegistrationControllerProvider(hostId)
                                      .notifier,
                                )
                                .install,
                      child: Text(
                        cli.value?.ready == true ? 'Update' : 'Register',
                      ),
                    ),
                  ],
                ),
                const Divider(height: AleraTokens.spaceXl),
                _SkillInstaller(
                  hostId: hostId,
                  skill: 'cli',
                  title: 'Alera CLI Skill',
                ),
                const Divider(height: AleraTokens.spaceXl),
                _SkillInstaller(
                  hostId: hostId,
                  skill: 'orchestration',
                  title: 'Alera Orchestration Skill',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SkillInstaller extends ConsumerWidget {
  const _SkillInstaller({
    required this.hostId,
    required this.skill,
    required this.title,
  });

  final String hostId;
  final String skill;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final install = ref.watch(skillInstallControllerProvider(hostId, skill));
    final runner = ref.watch(skillRunnerSelectionProvider(hostId, skill));
    final busy = install.phase == 'installing';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title),
        const SizedBox(height: AleraTokens.spaceSm),
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: runner,
                decoration: const InputDecoration(labelText: 'Runner'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'auto', child: Text('Auto')),
                  DropdownMenuItem(value: 'npx', child: Text('npx')),
                  DropdownMenuItem(value: 'bunx', child: Text('bunx')),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) {
                          ref
                              .read(
                                skillRunnerSelectionProvider(
                                  hostId,
                                  skill,
                                ).notifier,
                              )
                              .select(value);
                        }
                      },
              ),
            ),
            const SizedBox(width: AleraTokens.spaceMd),
            FilledButton.tonalIcon(
              onPressed: busy
                  ? null
                  : () => ref
                        .read(
                          skillInstallControllerProvider(
                            hostId,
                            skill,
                          ).notifier,
                        )
                        .install(runner),
              icon: busy
                  ? const SizedBox.square(
                      dimension: AleraTokens.spaceLg,
                      child: CircularProgressIndicator(
                        strokeWidth: AleraTokens.strokeSm,
                      ),
                    )
                  : const Icon(Icons.download_outlined),
              label: const Text('Install Or Update'),
            ),
          ],
        ),
        if (install.message != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceSm),
          Text(
            install.message!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: install.phase == 'failed'
                  ? AleraTokens.error
                  : install.phase == 'completed'
                  ? AleraTokens.success
                  : AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
  }
}
