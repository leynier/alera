/// Approval state of a run's execution policy.
enum RunPolicyStatus {
  /// No plan was ever proposed. The run schedules as it always did.
  none,

  /// Proposed and waiting on the user. Scheduling is held.
  draft,
  approved,
  rejected;

  static RunPolicyStatus parse(Object? value) {
    return switch (value) {
      'draft' => RunPolicyStatus.draft,
      'approved' => RunPolicyStatus.approved,
      'rejected' => RunPolicyStatus.rejected,
      _ => RunPolicyStatus.none,
    };
  }

  bool get isPending => this == RunPolicyStatus.draft;
}

/// One stage of a plan: which profile runs it, and what to fall back to.
class const RunPolicyStage({
  required final String id,
  required final String profile,
  final String? title,
  final List<String> fallbacks = const <String>[],
}) {
  factory fromJson(Map<String, Object?> json) {
    final rawFallbacks = json['fallbacks'];
    return RunPolicyStage(
      id: json['id'] as String? ?? '',
      profile: json['profile'] as String? ?? '',
      title: json['title'] as String?,
      fallbacks: rawFallbacks is List
          ? <String>[
              for (final entry in rawFallbacks)
                if (entry is String) entry,
            ]
          : const <String>[],
    );
  }

  String get label => title?.trim().isNotEmpty == true ? title!.trim() : id;
}

/// A run's plan together with its approval state.
class const RunExecutionPolicy({
  required final String runId,
  required final String workspaceId,
  required final RunPolicyStatus status,
  required this.blocksDispatch,
  final List<RunPolicyStage> stages = const <RunPolicyStage>[],
  final String stallPolicy = 'ask',
  final DateTime? updatedAt,
}) {
  factory fromJson(Map<String, Object?> json) {
    final policy = json['policy'];
    final policyMap = policy is Map ? Map<String, Object?>.from(policy) : null;
    final rawStages = policyMap?['stages'];
    return RunExecutionPolicy(
      runId: json['runId'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      status: RunPolicyStatus.parse(json['status']),
      blocksDispatch: json['blocksDispatch'] as bool? ?? false,
      stallPolicy: policyMap?['stallPolicy'] as String? ?? 'ask',
      stages: rawStages is List
          ? <RunPolicyStage>[
              for (final stage in rawStages)
                if (stage is Map)
                  RunPolicyStage.fromJson(Map<String, Object?>.from(stage)),
            ]
          : const <RunPolicyStage>[],
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  /// True while the coordinator is holding scheduling on this plan.
  final bool blocksDispatch;

  bool get hasPolicy => status != RunPolicyStatus.none;
}
