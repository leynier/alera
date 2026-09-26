import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:flutter/material.dart';

class WorkflowSavedProposals extends StatefulWidget {
  const WorkflowSavedProposals({
    super.key,
    required this.repository,
    required this.onSelect,
    required this.onNew,
  });
  final WorkflowLifecycleRepository repository;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;
  @override
  State<WorkflowSavedProposals> createState() => _WorkflowSavedProposalsState();
}

class _WorkflowSavedProposalsState extends State<WorkflowSavedProposals> {
  final _entries = <Map<String, Object?>>[];
  bool _busy = true;
  bool _more = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final last = reset || _entries.isEmpty ? null : _entries.last;
      final page = await widget.repository.request('workflows.proposals', {
        if (last != null) 'beforeCreatedAt': last['createdAt'],
        if (last != null) 'beforeId': last['id'],
      });
      if (!mounted) return;
      setState(() {
        if (reset) _entries.clear();
        final ids = _entries.map((entry) => entry['id']).toSet();
        for (final entry in (page['entries']! as List).cast<Map>()) {
          if (ids.add(entry['id'])) {
            _entries.add(Map<String, Object?>.from(entry));
          }
        }
        _more = page['hasMore']! as bool;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(AleraTokens.space16),
    itemCount: _entries.length + 2,
    itemBuilder: (context, index) {
      if (index == 0) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved Proposals',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.space8),
            const Text(
              'Resume a saved proposal without launching another coordinator.',
            ),
            Wrap(
              spacing: AleraTokens.space8,
              children: [
                TextButton(
                  onPressed: widget.onNew,
                  child: const Text('New Proposal'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _load(reset: true),
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ],
        );
      }
      if (index == _entries.length + 1) {
        return Column(
          children: [
            if (_error != null) SelectableText(_error.toString()),
            if (_entries.isEmpty && !_busy && _error == null)
              const Text('There are no saved proposals yet.'),
            if (_more)
              OutlinedButton(
                onPressed: _busy ? null : _load,
                child: const Text('Load More Proposals'),
              ),
            if (_busy) const Text('Loading proposals...'),
          ],
        );
      }
      final entry = _entries[index - 1];
      return AleraActivityRow(
        title: entry['objective']! as String,
        subtitle: entry['workspaceName'] as String? ?? 'Unavailable Workspace',
        metadata: switch (entry['cancellationStatus']) {
          'pending' => 'Cancelling',
          'settled' => 'Cancelled',
          'attention' => 'Cancellation Needs Attention',
          _ => entry['createdAt']! as String,
        },
        onPressed: () => widget.onSelect(entry['id']! as String),
      );
    },
  );
}
