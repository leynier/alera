import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';

enum AutomationBucket(final String label) {
  needsAttention('Needs Attention'),
  active('Active'),
  paused('Paused'),
  drafts('Drafts'),
  completed('Completed'),
  trash('Trash');

  bool contains(AutomationRecord automation) => switch (this) {
    needsAttention =>
      !automation.isTrashed &&
          (automation.state == 'blocked' || automation.attention != null),
    active => automation.state == 'active',
    paused => automation.state == 'paused',
    drafts => automation.state == 'draft',
    completed => automation.isCompleted,
    trash => automation.isTrashed,
  };
}

enum AutomationScopeKind { all, project, section, workspace }

/// Where the catalog is looking from. Global means every definition of the
/// connected runtime; the other scopes follow the runtime-derived association.
class const AutomationScope({
  final AutomationScopeKind kind = AutomationScopeKind.all,
  final String? id,
}) {
  static const AutomationScope all = AutomationScope();

  bool includes(AutomationRecord automation) => switch (kind) {
    AutomationScopeKind.all => true,
    AutomationScopeKind.project => automation.effectiveProjectId == id,
    AutomationScopeKind.section => automation.association?.sectionId == id,
    AutomationScopeKind.workspace => automation.associatedWorkspaceId == id,
  };

  @override
  bool operator ==(Object other) =>
      other is AutomationScope && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

class const AutomationCatalogFilters({
  final String search = '',
  final String? projectId,
  final String? hostId,
  final String? profileId,
  final String? tagId,
  final AutomationBucket? bucket,
}) {
  bool get isFiltered =>
      search.trim().isNotEmpty ||
      projectId != null ||
      hostId != null ||
      profileId != null ||
      tagId != null ||
      bucket != null;

  bool matches(AutomationRecord automation) {
    final bucket = this.bucket;
    if (bucket == null ? automation.isTrashed : !bucket.contains(automation)) {
      return false;
    }
    if (projectId != null && automation.effectiveProjectId != projectId) {
      return false;
    }
    if (hostId != null && automation.targetHostId != hostId) return false;
    if (profileId != null && automation.agentProfileId != profileId) {
      return false;
    }
    if (tagId != null && !automation.tagIds.contains(tagId)) return false;
    final query = search.trim().toLowerCase();
    return query.isEmpty ||
        automation.name.toLowerCase().contains(query) ||
        automation.slug.toLowerCase().contains(query) ||
        automation.description.toLowerCase().contains(query) ||
        automation.promptTemplate.toLowerCase().contains(query);
  }
}

/// Counts per bucket among the definitions inside [scope], ignoring the other
/// filters so the chips always show where definitions are.
Map<AutomationBucket, int> automationBucketCounts(
  Iterable<AutomationRecord> automations,
  AutomationScope scope,
) {
  final counts = <AutomationBucket, int>{
    for (final bucket in AutomationBucket.values) bucket: 0,
  };
  for (final automation in automations) {
    if (!scope.includes(automation)) continue;
    for (final bucket in AutomationBucket.values) {
      if (bucket.contains(automation)) {
        counts[bucket] = counts[bucket]! + 1;
      }
    }
  }
  return counts;
}

List<AutomationRecord> visibleAutomations(
  Iterable<AutomationRecord> automations,
  AutomationScope scope,
  AutomationCatalogFilters filters,
) {
  final visible = automations
      .where((item) => scope.includes(item) && filters.matches(item))
      .toList();
  visible.sort((left, right) {
    final attention = _attentionRank(left).compareTo(_attentionRank(right));
    if (attention != 0) return attention;
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  });
  return visible;
}

int _attentionRank(AutomationRecord automation) =>
    AutomationBucket.needsAttention.contains(automation) ? 0 : 1;
