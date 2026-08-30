import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

class const HostDirectoryRoot({
  required final String name,
  required final String path,
}) {
  factory fromJson(Map<String, Object?> json) {
    return HostDirectoryRoot(
      name: json.requiredString('name'),
      path: json.requiredString('path'),
    );
  }
}

class const HostDirectoryEntry({
  required final String name,
  required final String path,
  required final bool isSymlink,
}) {
  factory fromJson(Map<String, Object?> json) {
    return HostDirectoryEntry(
      name: json.requiredString('name'),
      path: json.requiredString('path'),
      isSymlink: json['isSymlink'] == true,
    );
  }
}

class const HostDirectoryListing({
  required final String path,
  required final List<HostDirectoryEntry> entries,
  final String? parentPath,
}) {
  factory fromJson(Map<String, Object?> json) {
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

class const ProjectRegistrationResult({
  required final ProjectSummary project,
  required final WorkspaceSummary mainWorkspace,
  required final bool created,
}) {
  factory fromJson(Map<String, Object?> json) {
    return ProjectRegistrationResult(
      project: .fromJson(asJsonMap(json['project'])),
      mainWorkspace: .fromJson(asJsonMap(json['mainWorkspace'])),
      created: json['created'] == true,
    );
  }
}

class const ProjectRemovalPreview({
  required final int workspaceCount,
  required final int tabCount,
  required final int activeSessionCount,
  required final bool hasConfigOverride,
}) {
  factory fromJson(Map<String, Object?> json) {
    return ProjectRemovalPreview(
      workspaceCount: json['workspaceCount'] as int? ?? 0,
      tabCount: json['tabCount'] as int? ?? 0,
      activeSessionCount: json['activeSessionCount'] as int? ?? 0,
      hasConfigOverride: json['hasConfigOverride'] == true,
    );
  }
}

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
  final String? workspaceId,
}) {
  bool get isActive =>
      status == ProjectCloneJobStatus.queued ||
      status == ProjectCloneJobStatus.running;

  factory fromJson(Map<String, Object?> json) {
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

class const ProjectConfigCopyRule({
  required final String from,
  final String? to,
  final bool overwrite = false,
}) {
  factory fromJson(Map<String, Object?> json) {
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

class const MobileProjectConfig({
  final List<ProjectConfigCopyRule> copyRules = const <ProjectConfigCopyRule>[],
  final List<String> setupCommands = const <String>[],
  final String promptAppend = '',
  final String? gitHostingProvider,
}) {
  factory fromJson(Map<String, Object?> json) {
    final worktree = asJsonMap(json['worktree']);
    final newWorkspace = asJsonMap(json['newWorkspace']);
    return MobileProjectConfig(
      copyRules: <ProjectConfigCopyRule>[
        for (final item
            in worktree['copy'] as List<Object?>? ?? const <Object?>[])
          ProjectConfigCopyRule.fromJson(asJsonMap(item)),
      ],
      setupCommands: worktree.stringList('setup'),
      promptAppend: newWorkspace.optionalString('promptAppend') ?? '',
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
    'newWorkspace': <String, Object?>{'promptAppend': promptAppend.trim()},
    'gitHostingProvider': ?gitHostingProvider,
  };
}

class const EffectiveMobileProjectConfig({
  required final MobileProjectConfig config,
  required final String origin,
  final String? error,
}) {
  factory fromJson(Map<String, Object?> json) {
    return EffectiveMobileProjectConfig(
      config: .fromJson(asJsonMap(json['config'])),
      origin: json.optionalString('origin') ?? 'none',
      error: json.optionalString('error'),
    );
  }
}
