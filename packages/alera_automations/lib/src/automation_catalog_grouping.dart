import 'package:alera_automations/src/automation_catalog_query.dart';
import 'package:alera_automations/src/automation_models.dart';

/// One header of the catalog and the definitions under it, already sorted.
/// A null [key] is the group of definitions the key function could not place.
class const AutomationGroup({
  required final String? key,
  required final String label,
  required final List<AutomationRecord> automations,
});

const List<String> _stateOrder = <String>[
  'active',
  'blocked',
  'paused',
  'draft',
  'archived',
  'trashed',
];

int _stateRank(AutomationRecord automation) {
  final rank = _stateOrder.indexOf(automation.state);
  return rank < 0 ? _stateOrder.indexOf('draft') : rank;
}

int _attentionRank(AutomationRecord automation) =>
    AutomationBucket.needsAttention.contains(automation) ? 0 : 1;

/// Catalog order: definitions that need attention first, then by state
/// (active, blocked, paused, draft, completed, trashed), then by name.
int compareAutomationsForCatalog(
  AutomationRecord left,
  AutomationRecord right,
) {
  final attention = _attentionRank(left).compareTo(_attentionRank(right));
  if (attention != 0) return attention;
  final state = _stateRank(left).compareTo(_stateRank(right));
  if (state != 0) return state;
  final name = left.name.toLowerCase().compareTo(right.name.toLowerCase());
  return name != 0 ? name : left.id.compareTo(right.id);
}

/// Groups [automations] by [keyOf], each key appearing once. Groups are
/// ordered by label, with the unplaced group, labelled [othersLabel], last.
List<AutomationGroup> groupAutomations(
  Iterable<AutomationRecord> automations, {
  required String? Function(AutomationRecord automation) keyOf,
  required String Function(String key) labelOf,
  String othersLabel = 'Others',
}) {
  final buckets = <String?, List<AutomationRecord>>{};
  for (final automation in automations) {
    (buckets[keyOf(automation)] ??= <AutomationRecord>[]).add(automation);
  }
  final groups = <AutomationGroup>[
    for (final MapEntry(:key, :value) in buckets.entries)
      AutomationGroup(
        key: key,
        label: key == null ? othersLabel : labelOf(key),
        automations: List<AutomationRecord>.unmodifiableOf(
          value..sort(compareAutomationsForCatalog),
        ),
      ),
  ];
  groups.sort((left, right) {
    if ((left.key == null) != (right.key == null)) {
      return left.key == null ? 1 : -1;
    }
    final label = left.label.toLowerCase().compareTo(right.label.toLowerCase());
    return label != 0 ? label : (left.key ?? '').compareTo(right.key ?? '');
  });
  return groups;
}
