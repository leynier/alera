enum ProjectCloneJobStatus { queued, running, completed, failed, cancelled }

class const ProjectCloneJob({
  required final String id,
  required final String source,
  required final String destinationPath,
  required final ProjectCloneJobStatus status,
  required final String phase,
  required final DateTime updatedAt,
  final int? progressPercent,
  final String? message,
  final String? error,
  final String? projectId,
  final String? projectName,
  final String? workspaceId,
}) {
  bool get isActive =>
      status == ProjectCloneJobStatus.queued ||
      status == ProjectCloneJobStatus.running;

  factory fromJson(Map<String, Object?> json) {
    return ProjectCloneJob(
      id: json['id'] as String? ?? '',
      source: json['source'] as String? ?? '',
      destinationPath: json['destinationPath'] as String? ?? '',
      status: ProjectCloneJobStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => ProjectCloneJobStatus.failed,
      ),
      phase: json['phase'] as String? ?? 'cloning',
      progressPercent: json['progressPercent'] as int?,
      message: json['message'] as String?,
      error: json['error'] as String?,
      projectId: json['projectId'] as String?,
      projectName: json['projectName'] as String?,
      workspaceId: json['workspaceId'] as String?,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}
