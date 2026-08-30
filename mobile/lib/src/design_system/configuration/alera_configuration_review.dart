import 'dart:convert';

import 'package:alera_configuration/alera_configuration.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class AleraConfigurationReview extends StatelessWidget {
  const AleraConfigurationReview({
    super.key,
    required this.target,
    required this.state,
    required this.onRefresh,
    required this.onHistory,
    required this.onRestore,
    required this.onChoice,
    required this.onRename,
    required this.onChooseAll,
    required this.onApply,
    required this.onRetry,
  });
  final String target;
  final ConfigurationScreenState state;
  final VoidCallback onRefresh, onHistory, onRetry;
  final ValueChanged<int> onRestore;
  final void Function(ConfigurationDifference, ConfigurationChoice) onChoice;
  final void Function(ConfigurationDifference, String) onRename;
  final ValueChanged<ConfigurationChoice> onChooseAll;
  final ValueChanged<bool> onApply;
  @override
  Widget build(BuildContext context) {
    final review = state.review;
    final differences = review?.merge.differences ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Target: $target', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.space12),
        const Text(
          'Configuration is stored in your Alera account and can be read by the service. Review custom commands and prompts for embedded secrets. Credentials and device permissions stay local.',
        ),
        const SizedBox(height: AleraTokens.space12),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            OutlinedButton(
              onPressed: state.busy ? null : onRefresh,
              child: const Text('Review Changes'),
            ),
            OutlinedButton(
              onPressed: state.busy ? null : onHistory,
              child: const Text('History'),
            ),
            if (review?.local.pending != null)
              OutlinedButton(
                onPressed: state.busy ? null : onRetry,
                child: const Text('Retry Pending Upload'),
              ),
          ],
        ),
        if (state.busy) const LinearProgressIndicator(),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space12),
            child: SelectableText(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (review != null) ...[
          const SizedBox(height: AleraTokens.space12),
          Text(
            'Shared version: ${review.head?.revision ?? "None"} • Comparing: ${review.source?.revision ?? "Empty"}',
          ),
          Text(
            '${differences.length} differences • ${differences.where((d) => d.choice == null).length} unresolved',
          ),
          Wrap(
            spacing: AleraTokens.space8,
            children: [
              TextButton(
                onPressed: state.busy
                    ? null
                    : () => onChooseAll(ConfigurationChoice.local),
                child: const Text('Keep All Local'),
              ),
              TextButton(
                onPressed: state.busy
                    ? null
                    : () => onChooseAll(ConfigurationChoice.remote),
                child: const Text('Keep All Remote'),
              ),
            ],
          ),
          for (final difference in differences)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AleraTokens.space12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        difference.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (difference.conflict)
                        const Text(
                          'Both sides changed this value. Choose what to keep.',
                        ),
                      const SizedBox(height: AleraTokens.space8),
                      SelectableText('Local: ${_display(difference, true)}'),
                      const SizedBox(height: AleraTokens.space8),
                      SelectableText('Remote: ${_display(difference, false)}'),
                      DropdownButton<ConfigurationChoice>(
                        isExpanded: true,
                        value: difference.choice,
                        hint: const Text('Choose A Value'),
                        items: const [
                          DropdownMenuItem(
                            value: ConfigurationChoice.local,
                            child: Text('Keep Local'),
                          ),
                          DropdownMenuItem(
                            value: ConfigurationChoice.remote,
                            child: Text('Keep Remote'),
                          ),
                        ],
                        onChanged: state.busy
                            ? null
                            : (value) {
                                if (value != null) onChoice(difference, value);
                              },
                      ),
                      if (difference.choice != null && difference.canRename)
                        TextFormField(
                          key: ValueKey(
                            '${difference.label}/${difference.choice}',
                          ),
                          initialValue:
                              (difference.path.last == 'name'
                                      ? difference.result
                                      : jsonMap(difference.result)['name'])
                                  as String?,
                          decoration: InputDecoration(
                            labelText: difference.path.contains('textActions')
                                ? 'Action Name'
                                : 'Profile Name',
                          ),
                          onChanged: state.busy
                              ? null
                              : (value) => onRename(difference, value),
                        ),
                      SelectableText(
                        'Result: ${difference.choice == null
                            ? "Unresolved"
                            : difference.customResult != null
                            ? const JsonEncoder.withIndent("  ").convert(difference.result)
                            : _display(difference, difference.choice == ConfigurationChoice.local)}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Text('These changes apply only to $target.'),
          const SizedBox(height: AleraTokens.space8),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: [
              FilledButton(
                onPressed: state.busy || review.merge.hasUnresolved
                    ? null
                    : () => onApply(false),
                child: const Text('Apply To Device'),
              ),
              FilledButton(
                onPressed: state.busy || review.merge.hasUnresolved
                    ? null
                    : () => onApply(true),
                child: const Text('Apply And Upload'),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space12),
          const Text(
            'Leaving this screen without applying keeps your configuration unchanged. If upload fails after applying, local changes remain pending.',
          ),
        ],
        for (final item in state.history)
          ListTile(
            title: Text('Version ${item['revision']} • ${item['deviceName']}'),
            subtitle: Text('${item['createdAt']}\n${item['summary']}'),
            trailing: TextButton(
              onPressed: state.busy
                  ? null
                  : () => onRestore(item['revision'] as int),
              child: const Text('Compare'),
            ),
          ),
      ],
    );
  }

  String _display(ConfigurationDifference difference, bool local) {
    if (local ? difference.localAbsent : difference.remoteAbsent) {
      return '(Removed)';
    }
    return const JsonEncoder.withIndent('  ')
        .convert(local ? difference.local : difference.remote);
  }
}
