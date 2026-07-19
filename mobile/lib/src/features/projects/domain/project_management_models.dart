import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

class HostDirectoryRoot {
  const HostDirectoryRoot({required this.name, required this.path});

  final String name;
  final String path;

  factory HostDirectoryRoot.fromJson(Map<String, Object?> json) {
    return HostDirectoryRoot(
      name: json.requiredString('name'),
      path: json.requiredString('path'),
    );
  }
}

class HostDirectoryEntry {
  const HostDirectoryEntry({
    required this.name,
    required this.path,
    required this.isSymlink,
  });

  final String name;
  final String path;
  final bool isSymlink;

  factory HostDirectoryEntry.fromJson(Map<String, Object?> json) {
    return HostDirectoryEntry(
      name: json.requiredString('name'),
      path: json.requiredString('path'),
      isSymlink: json['isSymlink'] == true,
    );
  }
}

class HostDirectoryListing {
  const HostDirectoryListing({
    required this.path,
    required this.entries,
    this.parentPath,
  });

  final String path;
  final String? parentPath;
  final List<HostDirectoryEntry> entries;

  factory HostDirectoryListing.fromJson(Map<String, Object?> json) {
    return HostDirectoryListing(
      path: json.requiredString('path'),
      parentPath: json.optionalString('parentPath'),
      entries: <HostDirectoryEntry>[
        for (final item
            in json['entries'] as List<Object?>? ?? const <Object?>[])
          HostDirectoryEntry.fromJson(asJsonMap(item)),
      ],
    );
  }
}

class ProjectRegistrationResult {
  const ProjectRegistrationResult({
    required this.project,
    required this.mainWorkspace,
    required this.created,
  });

  final ProjectSummary project;
  final WorkspaceSummary mainWorkspace;
  final bool created;

  factory ProjectRegistrationResult.fromJson(Map<String, Object?> json) {
    return ProjectRegistrationResult(
      project: ProjectSummary.fromJson(asJsonMap(json['project'])),
      mainWorkspace: WorkspaceSummary.fromJson(
        asJsonMap(json['mainWorkspace']),
      ),
      created: json['created'] == true,
    );
  }
}

class ProjectRemovalPreview {
  const ProjectRemovalPreview({
    required this.workspaceCount,
    required this.tabCount,
    required this.activeSessionCount,
    required this.hasConfigOverride,
  });

  final int workspaceCount;
  final int tabCount;
  final int activeSessionCount;
  final bool hasConfigOverride;

  factory ProjectRemovalPreview.fromJson(Map<String, Object?> json) {
    return ProjectRemovalPreview(
      workspaceCount: json['workspaceCount'] as int? ?? 0,
      tabCount: json['tabCount'] as int? ?? 0,
      activeSessionCount: json['activeSessionCount'] as int? ?? 0,
      hasConfigOverride: json['hasConfigOverride'] == true,
    );
  }
}

enum ProjectCloneJobStatus { queued, running, completed, failed, cancelled }

class ProjectCloneJob {
  const ProjectCloneJob({
    required this.id,
    required this.source,
    required this.destinationPath,
    required this.status,
    required this.phase,
    required this.updatedAt,
    this.progressPercent,
    this.message,
    this.error,
    this.projectId,
    this.workspaceId,
  });

  final String id;
  final String source;
  final String destinationPath;
  final ProjectCloneJobStatus status;
  final String phase;
  final int? progressPercent;
  final String? message;
  final String? error;
  final String? projectId;
  final String? workspaceId;
  final DateTime updatedAt;

  bool get isActive =>
      status == ProjectCloneJobStatus.queued ||
      status == ProjectCloneJobStatus.running;

  factory ProjectCloneJob.fromJson(Map<String, Object?> json) {
    return ProjectCloneJob(
      id: json.requiredString('id'),
      source: json.requiredString('source'),
      destinationPath: json.requiredString('destinationPath'),
      status: ProjectCloneJobStatus.values.firstWhere(
        (value) => value.name == json.optionalString('status'),
        orElse: () => ProjectCloneJobStatus.failed,
      ),
      phase: json.optionalString('phase') ?? 'cloning',
      progressPercent: json['progressPercent'] as int?,
      message: json.optionalString('message'),
      error: json.optionalString('error'),
      projectId: json.optionalString('projectId'),
      workspaceId: json.optionalString('workspaceId'),
      updatedAt: json.optionalDateTime('updatedAt') ?? DateTime.now().toUtc(),
    );
  }
}

class ProjectConfigCopyRule {
  const ProjectConfigCopyRule({
    required this.from,
    this.to,
    this.overwrite = false,
  });

  final String from;
  final String? to;
  final bool overwrite;

  factory ProjectConfigCopyRule.fromJson(Map<String, Object?> json) {
    return ProjectConfigCopyRule(
      from: json.requiredString('from'),
      to: json.optionalString('to'),
      overwrite: json['overwrite'] == true,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'from': from,
    if (to != null && to!.trim().isNotEmpty) 'to': to,
    'overwrite': overwrite,
  };
}

class MobileProjectConfig {
  const MobileProjectConfig({
    this.copyRules = const <ProjectConfigCopyRule>[],
    this.setupCommands = const <String>[],
    this.gitHostingProvider,
  });

  final List<ProjectConfigCopyRule> copyRules;
  final List<String> setupCommands;
  final String? gitHostingProvider;

  factory MobileProjectConfig.fromJson(Map<String, Object?> json) {
    final worktree = asJsonMap(json['worktree']);
    return MobileProjectConfig(
      copyRules: <ProjectConfigCopyRule>[
        for (final item
            in worktree['copy'] as List<Object?>? ?? const <Object?>[])
          ProjectConfigCopyRule.fromJson(asJsonMap(item)),
      ],
      setupCommands: worktree.stringList('setup'),
      gitHostingProvider: json.optionalString('gitHostingProvider'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'worktree': <String, Object?>{
      'copy': <Map<String, Object?>>[
        for (final rule in copyRules) rule.toJson(),
      ],
      'setup': setupCommands,
    },
    if (gitHostingProvider != null) 'gitHostingProvider': gitHostingProvider,
  };
}

class EffectiveMobileProjectConfig {
  const EffectiveMobileProjectConfig({
    required this.config,
    required this.origin,
    this.error,
  });

  final MobileProjectConfig config;
  final String origin;
  final String? error;

  factory EffectiveMobileProjectConfig.fromJson(Map<String, Object?> json) {
    return EffectiveMobileProjectConfig(
      config: MobileProjectConfig.fromJson(asJsonMap(json['config'])),
      origin: json.optionalString('origin') ?? 'none',
      error: json.optionalString('error'),
    );
  }
}
