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
class RunPolicyStage {
  const RunPolicyStage({
    required this.id,
    required this.profile,
    this.title,
    this.fallbacks = const <String>[],
  });

  factory RunPolicyStage.fromJson(Map<String, Object?> json) {
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

  final String id;
  final String profile;
  final String? title;
  final List<String> fallbacks;

  String get label => title?.trim().isNotEmpty == true ? title!.trim() : id;
}

/// A run's plan together with its approval state.
class RunExecutionPolicy {
  const RunExecutionPolicy({
    required this.runId,
    required this.workspaceId,
    required this.status,
    required this.blocksDispatch,
    this.stages = const <RunPolicyStage>[],
    this.stallPolicy = 'ask',
    this.updatedAt,
  });

  factory RunExecutionPolicy.fromJson(Map<String, Object?> json) {
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

  final String runId;
  final String workspaceId;
  final RunPolicyStatus status;

  /// True while the coordinator is holding scheduling on this plan.
  final bool blocksDispatch;
  final List<RunPolicyStage> stages;
  final String stallPolicy;
  final DateTime? updatedAt;

  bool get hasPolicy => status != RunPolicyStatus.none;
}
