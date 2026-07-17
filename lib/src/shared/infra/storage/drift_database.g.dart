// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_database.dart';

// ignore_for_file: type=lint
class $ProjectsTableTable extends ProjectsTable
    with TableInfo<$ProjectsTableTable, ProjectsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repoPathMeta = const VerificationMeta(
    'repoPath',
  );
  @override
  late final GeneratedColumn<String> repoPath = GeneratedColumn<String>(
    'repo_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    repoPath,
    createdAt,
    updatedAt,
    kind,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('repo_path')) {
      context.handle(
        _repoPathMeta,
        repoPath.isAcceptableOrUnknown(data['repo_path']!, _repoPathMeta),
      );
    } else if (isInserting) {
      context.missing(_repoPathMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      repoPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repo_path'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
    );
  }

  @override
  $ProjectsTableTable createAlias(String alias) {
    return $ProjectsTableTable(attachedDatabase, alias);
  }
}

class ProjectsTableData extends DataClass
    implements Insertable<ProjectsTableData> {
  final String id;
  final String name;
  final String repoPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String kind;
  const ProjectsTableData({
    required this.id,
    required this.name,
    required this.repoPath,
    required this.createdAt,
    required this.updatedAt,
    required this.kind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['repo_path'] = Variable<String>(repoPath);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['kind'] = Variable<String>(kind);
    return map;
  }

  ProjectsTableCompanion toCompanion(bool nullToAbsent) {
    return ProjectsTableCompanion(
      id: Value(id),
      name: Value(name),
      repoPath: Value(repoPath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      kind: Value(kind),
    );
  }

  factory ProjectsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectsTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      repoPath: serializer.fromJson<String>(json['repoPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      kind: serializer.fromJson<String>(json['kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'repoPath': serializer.toJson<String>(repoPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'kind': serializer.toJson<String>(kind),
    };
  }

  ProjectsTableData copyWith({
    String? id,
    String? name,
    String? repoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? kind,
  }) => ProjectsTableData(
    id: id ?? this.id,
    name: name ?? this.name,
    repoPath: repoPath ?? this.repoPath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    kind: kind ?? this.kind,
  );
  ProjectsTableData copyWithCompanion(ProjectsTableCompanion data) {
    return ProjectsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      repoPath: data.repoPath.present ? data.repoPath.value : this.repoPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      kind: data.kind.present ? data.kind.value : this.kind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('repoPath: $repoPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, repoPath, createdAt, updatedAt, kind);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.repoPath == this.repoPath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.kind == this.kind);
}

class ProjectsTableCompanion extends UpdateCompanion<ProjectsTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> repoPath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> kind;
  final Value<int> rowid;
  const ProjectsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.repoPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsTableCompanion.insert({
    required String id,
    required String name,
    required String repoPath,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String kind,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       repoPath = Value(repoPath),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       kind = Value(kind);
  static Insertable<ProjectsTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? repoPath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? kind,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (repoPath != null) 'repo_path': repoPath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (kind != null) 'kind': kind,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? repoPath,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? kind,
    Value<int>? rowid,
  }) {
    return ProjectsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      repoPath: repoPath ?? this.repoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      kind: kind ?? this.kind,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (repoPath.present) {
      map['repo_path'] = Variable<String>(repoPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('repoPath: $repoPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('kind: $kind, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkspacesTableTable extends WorkspacesTable
    with TableInfo<$WorkspacesTableTable, WorkspacesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkspacesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchMeta = const VerificationMeta('branch');
  @override
  late final GeneratedColumn<String> branch = GeneratedColumn<String>(
    'branch',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceBranchMeta = const VerificationMeta(
    'sourceBranch',
  );
  @override
  late final GeneratedColumn<String> sourceBranch = GeneratedColumn<String>(
    'source_branch',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reusesExistingBranchMeta =
      const VerificationMeta('reusesExistingBranch');
  @override
  late final GeneratedColumn<bool> reusesExistingBranch = GeneratedColumn<bool>(
    'reuses_existing_branch',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reuses_existing_branch" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    name,
    branch,
    path,
    createdAt,
    updatedAt,
    kind,
    status,
    sourceBranch,
    reusesExistingBranch,
    isPinned,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workspaces_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkspacesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('branch')) {
      context.handle(
        _branchMeta,
        branch.isAcceptableOrUnknown(data['branch']!, _branchMeta),
      );
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('source_branch')) {
      context.handle(
        _sourceBranchMeta,
        sourceBranch.isAcceptableOrUnknown(
          data['source_branch']!,
          _sourceBranchMeta,
        ),
      );
    }
    if (data.containsKey('reuses_existing_branch')) {
      context.handle(
        _reusesExistingBranchMeta,
        reusesExistingBranch.isAcceptableOrUnknown(
          data['reuses_existing_branch']!,
          _reusesExistingBranchMeta,
        ),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkspacesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkspacesTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      branch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch'],
      ),
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      sourceBranch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_branch'],
      ),
      reusesExistingBranch: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reuses_existing_branch'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
    );
  }

  @override
  $WorkspacesTableTable createAlias(String alias) {
    return $WorkspacesTableTable(attachedDatabase, alias);
  }
}

class WorkspacesTableData extends DataClass
    implements Insertable<WorkspacesTableData> {
  final String id;
  final String projectId;
  final String name;
  final String? branch;
  final String path;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String kind;
  final String status;
  final String? sourceBranch;
  final bool reusesExistingBranch;
  final bool isPinned;
  const WorkspacesTableData({
    required this.id,
    required this.projectId,
    required this.name,
    this.branch,
    required this.path,
    required this.createdAt,
    required this.updatedAt,
    required this.kind,
    required this.status,
    this.sourceBranch,
    required this.reusesExistingBranch,
    required this.isPinned,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || branch != null) {
      map['branch'] = Variable<String>(branch);
    }
    map['path'] = Variable<String>(path);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['kind'] = Variable<String>(kind);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || sourceBranch != null) {
      map['source_branch'] = Variable<String>(sourceBranch);
    }
    map['reuses_existing_branch'] = Variable<bool>(reusesExistingBranch);
    map['is_pinned'] = Variable<bool>(isPinned);
    return map;
  }

  WorkspacesTableCompanion toCompanion(bool nullToAbsent) {
    return WorkspacesTableCompanion(
      id: Value(id),
      projectId: Value(projectId),
      name: Value(name),
      branch: branch == null && nullToAbsent
          ? const Value.absent()
          : Value(branch),
      path: Value(path),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      kind: Value(kind),
      status: Value(status),
      sourceBranch: sourceBranch == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceBranch),
      reusesExistingBranch: Value(reusesExistingBranch),
      isPinned: Value(isPinned),
    );
  }

  factory WorkspacesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkspacesTableData(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      name: serializer.fromJson<String>(json['name']),
      branch: serializer.fromJson<String?>(json['branch']),
      path: serializer.fromJson<String>(json['path']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      kind: serializer.fromJson<String>(json['kind']),
      status: serializer.fromJson<String>(json['status']),
      sourceBranch: serializer.fromJson<String?>(json['sourceBranch']),
      reusesExistingBranch: serializer.fromJson<bool>(
        json['reusesExistingBranch'],
      ),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'name': serializer.toJson<String>(name),
      'branch': serializer.toJson<String?>(branch),
      'path': serializer.toJson<String>(path),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'kind': serializer.toJson<String>(kind),
      'status': serializer.toJson<String>(status),
      'sourceBranch': serializer.toJson<String?>(sourceBranch),
      'reusesExistingBranch': serializer.toJson<bool>(reusesExistingBranch),
      'isPinned': serializer.toJson<bool>(isPinned),
    };
  }

  WorkspacesTableData copyWith({
    String? id,
    String? projectId,
    String? name,
    Value<String?> branch = const Value.absent(),
    String? path,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? kind,
    String? status,
    Value<String?> sourceBranch = const Value.absent(),
    bool? reusesExistingBranch,
    bool? isPinned,
  }) => WorkspacesTableData(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    name: name ?? this.name,
    branch: branch.present ? branch.value : this.branch,
    path: path ?? this.path,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    sourceBranch: sourceBranch.present ? sourceBranch.value : this.sourceBranch,
    reusesExistingBranch: reusesExistingBranch ?? this.reusesExistingBranch,
    isPinned: isPinned ?? this.isPinned,
  );
  WorkspacesTableData copyWithCompanion(WorkspacesTableCompanion data) {
    return WorkspacesTableData(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      name: data.name.present ? data.name.value : this.name,
      branch: data.branch.present ? data.branch.value : this.branch,
      path: data.path.present ? data.path.value : this.path,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      kind: data.kind.present ? data.kind.value : this.kind,
      status: data.status.present ? data.status.value : this.status,
      sourceBranch: data.sourceBranch.present
          ? data.sourceBranch.value
          : this.sourceBranch,
      reusesExistingBranch: data.reusesExistingBranch.present
          ? data.reusesExistingBranch.value
          : this.reusesExistingBranch,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkspacesTableData(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('name: $name, ')
          ..write('branch: $branch, ')
          ..write('path: $path, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('sourceBranch: $sourceBranch, ')
          ..write('reusesExistingBranch: $reusesExistingBranch, ')
          ..write('isPinned: $isPinned')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    name,
    branch,
    path,
    createdAt,
    updatedAt,
    kind,
    status,
    sourceBranch,
    reusesExistingBranch,
    isPinned,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspacesTableData &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.name == this.name &&
          other.branch == this.branch &&
          other.path == this.path &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.kind == this.kind &&
          other.status == this.status &&
          other.sourceBranch == this.sourceBranch &&
          other.reusesExistingBranch == this.reusesExistingBranch &&
          other.isPinned == this.isPinned);
}

class WorkspacesTableCompanion extends UpdateCompanion<WorkspacesTableData> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String> name;
  final Value<String?> branch;
  final Value<String> path;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> kind;
  final Value<String> status;
  final Value<String?> sourceBranch;
  final Value<bool> reusesExistingBranch;
  final Value<bool> isPinned;
  final Value<int> rowid;
  const WorkspacesTableCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.name = const Value.absent(),
    this.branch = const Value.absent(),
    this.path = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.status = const Value.absent(),
    this.sourceBranch = const Value.absent(),
    this.reusesExistingBranch = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkspacesTableCompanion.insert({
    required String id,
    required String projectId,
    required String name,
    this.branch = const Value.absent(),
    required String path,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String kind,
    required String status,
    this.sourceBranch = const Value.absent(),
    this.reusesExistingBranch = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       projectId = Value(projectId),
       name = Value(name),
       path = Value(path),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       kind = Value(kind),
       status = Value(status);
  static Insertable<WorkspacesTableData> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? name,
    Expression<String>? branch,
    Expression<String>? path,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? kind,
    Expression<String>? status,
    Expression<String>? sourceBranch,
    Expression<bool>? reusesExistingBranch,
    Expression<bool>? isPinned,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (name != null) 'name': name,
      if (branch != null) 'branch': branch,
      if (path != null) 'path': path,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (sourceBranch != null) 'source_branch': sourceBranch,
      if (reusesExistingBranch != null)
        'reuses_existing_branch': reusesExistingBranch,
      if (isPinned != null) 'is_pinned': isPinned,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkspacesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? projectId,
    Value<String>? name,
    Value<String?>? branch,
    Value<String>? path,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? kind,
    Value<String>? status,
    Value<String?>? sourceBranch,
    Value<bool>? reusesExistingBranch,
    Value<bool>? isPinned,
    Value<int>? rowid,
  }) {
    return WorkspacesTableCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      branch: branch ?? this.branch,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      sourceBranch: sourceBranch ?? this.sourceBranch,
      reusesExistingBranch: reusesExistingBranch ?? this.reusesExistingBranch,
      isPinned: isPinned ?? this.isPinned,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (branch.present) {
      map['branch'] = Variable<String>(branch.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (sourceBranch.present) {
      map['source_branch'] = Variable<String>(sourceBranch.value);
    }
    if (reusesExistingBranch.present) {
      map['reuses_existing_branch'] = Variable<bool>(
        reusesExistingBranch.value,
      );
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkspacesTableCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('name: $name, ')
          ..write('branch: $branch, ')
          ..write('path: $path, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('sourceBranch: $sourceBranch, ')
          ..write('reusesExistingBranch: $reusesExistingBranch, ')
          ..write('isPinned: $isPinned, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkspaceTabsTableTable extends WorkspaceTabsTable
    with TableInfo<$WorkspaceTabsTableTable, WorkspaceTabsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkspaceTabsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    kind,
    title,
    createdAt,
    updatedAt,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workspace_tabs_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkspaceTabsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkspaceTabsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkspaceTabsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $WorkspaceTabsTableTable createAlias(String alias) {
    return $WorkspaceTabsTableTable(attachedDatabase, alias);
  }
}

class WorkspaceTabsTableData extends DataClass
    implements Insertable<WorkspaceTabsTableData> {
  final String id;
  final String workspaceId;
  final String kind;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String payloadJson;
  const WorkspaceTabsTableData({
    required this.id,
    required this.workspaceId,
    required this.kind,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['kind'] = Variable<String>(kind);
    map['title'] = Variable<String>(title);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  WorkspaceTabsTableCompanion toCompanion(bool nullToAbsent) {
    return WorkspaceTabsTableCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      kind: Value(kind),
      title: Value(title),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      payloadJson: Value(payloadJson),
    );
  }

  factory WorkspaceTabsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkspaceTabsTableData(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      kind: serializer.fromJson<String>(json['kind']),
      title: serializer.fromJson<String>(json['title']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'kind': serializer.toJson<String>(kind),
      'title': serializer.toJson<String>(title),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  WorkspaceTabsTableData copyWith({
    String? id,
    String? workspaceId,
    String? kind,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? payloadJson,
  }) => WorkspaceTabsTableData(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  WorkspaceTabsTableData copyWithCompanion(WorkspaceTabsTableCompanion data) {
    return WorkspaceTabsTableData(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      kind: data.kind.present ? data.kind.value : this.kind,
      title: data.title.present ? data.title.value : this.title,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkspaceTabsTableData(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    kind,
    title,
    createdAt,
    updatedAt,
    payloadJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceTabsTableData &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.kind == this.kind &&
          other.title == this.title &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.payloadJson == this.payloadJson);
}

class WorkspaceTabsTableCompanion
    extends UpdateCompanion<WorkspaceTabsTableData> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> kind;
  final Value<String> title;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> payloadJson;
  final Value<int> rowid;
  const WorkspaceTabsTableCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.kind = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkspaceTabsTableCompanion.insert({
    required String id,
    required String workspaceId,
    required String kind,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       kind = Value(kind),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<WorkspaceTabsTableData> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? kind,
    Expression<String>? title,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (kind != null) 'kind': kind,
      if (title != null) 'title': title,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkspaceTabsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? kind,
    Value<String>? title,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? payloadJson,
    Value<int>? rowid,
  }) {
    return WorkspaceTabsTableCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkspaceTabsTableCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('kind: $kind, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkbenchLayoutsTableTable extends WorkbenchLayoutsTable
    with TableInfo<$WorkbenchLayoutsTableTable, WorkbenchLayoutsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkbenchLayoutsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [workspaceId, dataJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workbench_layouts_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkbenchLayoutsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {workspaceId};
  @override
  WorkbenchLayoutsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkbenchLayoutsTableData(
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
    );
  }

  @override
  $WorkbenchLayoutsTableTable createAlias(String alias) {
    return $WorkbenchLayoutsTableTable(attachedDatabase, alias);
  }
}

class WorkbenchLayoutsTableData extends DataClass
    implements Insertable<WorkbenchLayoutsTableData> {
  final String workspaceId;
  final String dataJson;
  const WorkbenchLayoutsTableData({
    required this.workspaceId,
    required this.dataJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workspace_id'] = Variable<String>(workspaceId);
    map['data_json'] = Variable<String>(dataJson);
    return map;
  }

  WorkbenchLayoutsTableCompanion toCompanion(bool nullToAbsent) {
    return WorkbenchLayoutsTableCompanion(
      workspaceId: Value(workspaceId),
      dataJson: Value(dataJson),
    );
  }

  factory WorkbenchLayoutsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkbenchLayoutsTableData(
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workspaceId': serializer.toJson<String>(workspaceId),
      'dataJson': serializer.toJson<String>(dataJson),
    };
  }

  WorkbenchLayoutsTableData copyWith({String? workspaceId, String? dataJson}) =>
      WorkbenchLayoutsTableData(
        workspaceId: workspaceId ?? this.workspaceId,
        dataJson: dataJson ?? this.dataJson,
      );
  WorkbenchLayoutsTableData copyWithCompanion(
    WorkbenchLayoutsTableCompanion data,
  ) {
    return WorkbenchLayoutsTableData(
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkbenchLayoutsTableData(')
          ..write('workspaceId: $workspaceId, ')
          ..write('dataJson: $dataJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(workspaceId, dataJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkbenchLayoutsTableData &&
          other.workspaceId == this.workspaceId &&
          other.dataJson == this.dataJson);
}

class WorkbenchLayoutsTableCompanion
    extends UpdateCompanion<WorkbenchLayoutsTableData> {
  final Value<String> workspaceId;
  final Value<String> dataJson;
  final Value<int> rowid;
  const WorkbenchLayoutsTableCompanion({
    this.workspaceId = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkbenchLayoutsTableCompanion.insert({
    required String workspaceId,
    required String dataJson,
    this.rowid = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       dataJson = Value(dataJson);
  static Insertable<WorkbenchLayoutsTableData> custom({
    Expression<String>? workspaceId,
    Expression<String>? dataJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (dataJson != null) 'data_json': dataJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkbenchLayoutsTableCompanion copyWith({
    Value<String>? workspaceId,
    Value<String>? dataJson,
    Value<int>? rowid,
  }) {
    return WorkbenchLayoutsTableCompanion(
      workspaceId: workspaceId ?? this.workspaceId,
      dataJson: dataJson ?? this.dataJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkbenchLayoutsTableCompanion(')
          ..write('workspaceId: $workspaceId, ')
          ..write('dataJson: $dataJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkbenchViewPrefsTableTable extends WorkbenchViewPrefsTable
    with TableInfo<$WorkbenchViewPrefsTableTable, WorkbenchViewPrefsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkbenchViewPrefsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, dataJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workbench_view_prefs_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkbenchViewPrefsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkbenchViewPrefsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkbenchViewPrefsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
    );
  }

  @override
  $WorkbenchViewPrefsTableTable createAlias(String alias) {
    return $WorkbenchViewPrefsTableTable(attachedDatabase, alias);
  }
}

class WorkbenchViewPrefsTableData extends DataClass
    implements Insertable<WorkbenchViewPrefsTableData> {
  final int id;
  final String dataJson;
  const WorkbenchViewPrefsTableData({required this.id, required this.dataJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['data_json'] = Variable<String>(dataJson);
    return map;
  }

  WorkbenchViewPrefsTableCompanion toCompanion(bool nullToAbsent) {
    return WorkbenchViewPrefsTableCompanion(
      id: Value(id),
      dataJson: Value(dataJson),
    );
  }

  factory WorkbenchViewPrefsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkbenchViewPrefsTableData(
      id: serializer.fromJson<int>(json['id']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'dataJson': serializer.toJson<String>(dataJson),
    };
  }

  WorkbenchViewPrefsTableData copyWith({int? id, String? dataJson}) =>
      WorkbenchViewPrefsTableData(
        id: id ?? this.id,
        dataJson: dataJson ?? this.dataJson,
      );
  WorkbenchViewPrefsTableData copyWithCompanion(
    WorkbenchViewPrefsTableCompanion data,
  ) {
    return WorkbenchViewPrefsTableData(
      id: data.id.present ? data.id.value : this.id,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkbenchViewPrefsTableData(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, dataJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkbenchViewPrefsTableData &&
          other.id == this.id &&
          other.dataJson == this.dataJson);
}

class WorkbenchViewPrefsTableCompanion
    extends UpdateCompanion<WorkbenchViewPrefsTableData> {
  final Value<int> id;
  final Value<String> dataJson;
  const WorkbenchViewPrefsTableCompanion({
    this.id = const Value.absent(),
    this.dataJson = const Value.absent(),
  });
  WorkbenchViewPrefsTableCompanion.insert({
    this.id = const Value.absent(),
    required String dataJson,
  }) : dataJson = Value(dataJson);
  static Insertable<WorkbenchViewPrefsTableData> custom({
    Expression<int>? id,
    Expression<String>? dataJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dataJson != null) 'data_json': dataJson,
    });
  }

  WorkbenchViewPrefsTableCompanion copyWith({
    Value<int>? id,
    Value<String>? dataJson,
  }) {
    return WorkbenchViewPrefsTableCompanion(
      id: id ?? this.id,
      dataJson: dataJson ?? this.dataJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkbenchViewPrefsTableCompanion(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTableTable extends AppSettingsTable
    with TableInfo<$AppSettingsTableTable, AppSettingsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, dataJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSettingsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
    );
  }

  @override
  $AppSettingsTableTable createAlias(String alias) {
    return $AppSettingsTableTable(attachedDatabase, alias);
  }
}

class AppSettingsTableData extends DataClass
    implements Insertable<AppSettingsTableData> {
  final int id;
  final String dataJson;
  const AppSettingsTableData({required this.id, required this.dataJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['data_json'] = Variable<String>(dataJson);
    return map;
  }

  AppSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsTableCompanion(id: Value(id), dataJson: Value(dataJson));
  }

  factory AppSettingsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingsTableData(
      id: serializer.fromJson<int>(json['id']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'dataJson': serializer.toJson<String>(dataJson),
    };
  }

  AppSettingsTableData copyWith({int? id, String? dataJson}) =>
      AppSettingsTableData(
        id: id ?? this.id,
        dataJson: dataJson ?? this.dataJson,
      );
  AppSettingsTableData copyWithCompanion(AppSettingsTableCompanion data) {
    return AppSettingsTableData(
      id: data.id.present ? data.id.value : this.id,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsTableData(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, dataJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingsTableData &&
          other.id == this.id &&
          other.dataJson == this.dataJson);
}

class AppSettingsTableCompanion extends UpdateCompanion<AppSettingsTableData> {
  final Value<int> id;
  final Value<String> dataJson;
  const AppSettingsTableCompanion({
    this.id = const Value.absent(),
    this.dataJson = const Value.absent(),
  });
  AppSettingsTableCompanion.insert({
    this.id = const Value.absent(),
    required String dataJson,
  }) : dataJson = Value(dataJson);
  static Insertable<AppSettingsTableData> custom({
    Expression<int>? id,
    Expression<String>? dataJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dataJson != null) 'data_json': dataJson,
    });
  }

  AppSettingsTableCompanion copyWith({
    Value<int>? id,
    Value<String>? dataJson,
  }) {
    return AppSettingsTableCompanion(
      id: id ?? this.id,
      dataJson: dataJson ?? this.dataJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsTableCompanion(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson')
          ..write(')'))
        .toString();
  }
}

class $ProjectConfigsTableTable extends ProjectConfigsTable
    with TableInfo<$ProjectConfigsTableTable, ProjectConfigsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectConfigsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [projectId, dataJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_configs_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectConfigsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {projectId};
  @override
  ProjectConfigsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectConfigsTableData(
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProjectConfigsTableTable createAlias(String alias) {
    return $ProjectConfigsTableTable(attachedDatabase, alias);
  }
}

class ProjectConfigsTableData extends DataClass
    implements Insertable<ProjectConfigsTableData> {
  final String projectId;
  final String dataJson;
  final DateTime updatedAt;
  const ProjectConfigsTableData({
    required this.projectId,
    required this.dataJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['project_id'] = Variable<String>(projectId);
    map['data_json'] = Variable<String>(dataJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProjectConfigsTableCompanion toCompanion(bool nullToAbsent) {
    return ProjectConfigsTableCompanion(
      projectId: Value(projectId),
      dataJson: Value(dataJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProjectConfigsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectConfigsTableData(
      projectId: serializer.fromJson<String>(json['projectId']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'projectId': serializer.toJson<String>(projectId),
      'dataJson': serializer.toJson<String>(dataJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProjectConfigsTableData copyWith({
    String? projectId,
    String? dataJson,
    DateTime? updatedAt,
  }) => ProjectConfigsTableData(
    projectId: projectId ?? this.projectId,
    dataJson: dataJson ?? this.dataJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProjectConfigsTableData copyWithCompanion(ProjectConfigsTableCompanion data) {
    return ProjectConfigsTableData(
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectConfigsTableData(')
          ..write('projectId: $projectId, ')
          ..write('dataJson: $dataJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(projectId, dataJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectConfigsTableData &&
          other.projectId == this.projectId &&
          other.dataJson == this.dataJson &&
          other.updatedAt == this.updatedAt);
}

class ProjectConfigsTableCompanion
    extends UpdateCompanion<ProjectConfigsTableData> {
  final Value<String> projectId;
  final Value<String> dataJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProjectConfigsTableCompanion({
    this.projectId = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectConfigsTableCompanion.insert({
    required String projectId,
    required String dataJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : projectId = Value(projectId),
       dataJson = Value(dataJson),
       updatedAt = Value(updatedAt);
  static Insertable<ProjectConfigsTableData> custom({
    Expression<String>? projectId,
    Expression<String>? dataJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (projectId != null) 'project_id': projectId,
      if (dataJson != null) 'data_json': dataJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectConfigsTableCompanion copyWith({
    Value<String>? projectId,
    Value<String>? dataJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProjectConfigsTableCompanion(
      projectId: projectId ?? this.projectId,
      dataJson: dataJson ?? this.dataJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectConfigsTableCompanion(')
          ..write('projectId: $projectId, ')
          ..write('dataJson: $dataJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppWindowStateTableTable extends AppWindowStateTable
    with TableInfo<$AppWindowStateTableTable, AppWindowStateTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppWindowStateTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, dataJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_window_state_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppWindowStateTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_dataJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppWindowStateTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppWindowStateTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppWindowStateTableTable createAlias(String alias) {
    return $AppWindowStateTableTable(attachedDatabase, alias);
  }
}

class AppWindowStateTableData extends DataClass
    implements Insertable<AppWindowStateTableData> {
  final int id;
  final String dataJson;
  final DateTime updatedAt;
  const AppWindowStateTableData({
    required this.id,
    required this.dataJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['data_json'] = Variable<String>(dataJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppWindowStateTableCompanion toCompanion(bool nullToAbsent) {
    return AppWindowStateTableCompanion(
      id: Value(id),
      dataJson: Value(dataJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppWindowStateTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppWindowStateTableData(
      id: serializer.fromJson<int>(json['id']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'dataJson': serializer.toJson<String>(dataJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppWindowStateTableData copyWith({
    int? id,
    String? dataJson,
    DateTime? updatedAt,
  }) => AppWindowStateTableData(
    id: id ?? this.id,
    dataJson: dataJson ?? this.dataJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AppWindowStateTableData copyWithCompanion(AppWindowStateTableCompanion data) {
    return AppWindowStateTableData(
      id: data.id.present ? data.id.value : this.id,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppWindowStateTableData(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, dataJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppWindowStateTableData &&
          other.id == this.id &&
          other.dataJson == this.dataJson &&
          other.updatedAt == this.updatedAt);
}

class AppWindowStateTableCompanion
    extends UpdateCompanion<AppWindowStateTableData> {
  final Value<int> id;
  final Value<String> dataJson;
  final Value<DateTime> updatedAt;
  const AppWindowStateTableCompanion({
    this.id = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  AppWindowStateTableCompanion.insert({
    this.id = const Value.absent(),
    required String dataJson,
    required DateTime updatedAt,
  }) : dataJson = Value(dataJson),
       updatedAt = Value(updatedAt);
  static Insertable<AppWindowStateTableData> custom({
    Expression<int>? id,
    Expression<String>? dataJson,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dataJson != null) 'data_json': dataJson,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  AppWindowStateTableCompanion copyWith({
    Value<int>? id,
    Value<String>? dataJson,
    Value<DateTime>? updatedAt,
  }) {
    return AppWindowStateTableCompanion(
      id: id ?? this.id,
      dataJson: dataJson ?? this.dataJson,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppWindowStateTableCompanion(')
          ..write('id: $id, ')
          ..write('dataJson: $dataJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $WorkspaceActivityTableTable extends WorkspaceActivityTable
    with TableInfo<$WorkspaceActivityTableTable, WorkspaceActivityTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkspaceActivityTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastActivityAtMeta = const VerificationMeta(
    'lastActivityAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastActivityAt =
      GeneratedColumn<DateTime>(
        'last_activity_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [workspaceId, lastActivityAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workspace_activity_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkspaceActivityTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('last_activity_at')) {
      context.handle(
        _lastActivityAtMeta,
        lastActivityAt.isAcceptableOrUnknown(
          data['last_activity_at']!,
          _lastActivityAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastActivityAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {workspaceId};
  @override
  WorkspaceActivityTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkspaceActivityTableData(
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      lastActivityAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_activity_at'],
      )!,
    );
  }

  @override
  $WorkspaceActivityTableTable createAlias(String alias) {
    return $WorkspaceActivityTableTable(attachedDatabase, alias);
  }
}

class WorkspaceActivityTableData extends DataClass
    implements Insertable<WorkspaceActivityTableData> {
  final String workspaceId;
  final DateTime lastActivityAt;
  const WorkspaceActivityTableData({
    required this.workspaceId,
    required this.lastActivityAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workspace_id'] = Variable<String>(workspaceId);
    map['last_activity_at'] = Variable<DateTime>(lastActivityAt);
    return map;
  }

  WorkspaceActivityTableCompanion toCompanion(bool nullToAbsent) {
    return WorkspaceActivityTableCompanion(
      workspaceId: Value(workspaceId),
      lastActivityAt: Value(lastActivityAt),
    );
  }

  factory WorkspaceActivityTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkspaceActivityTableData(
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      lastActivityAt: serializer.fromJson<DateTime>(json['lastActivityAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workspaceId': serializer.toJson<String>(workspaceId),
      'lastActivityAt': serializer.toJson<DateTime>(lastActivityAt),
    };
  }

  WorkspaceActivityTableData copyWith({
    String? workspaceId,
    DateTime? lastActivityAt,
  }) => WorkspaceActivityTableData(
    workspaceId: workspaceId ?? this.workspaceId,
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
  );
  WorkspaceActivityTableData copyWithCompanion(
    WorkspaceActivityTableCompanion data,
  ) {
    return WorkspaceActivityTableData(
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      lastActivityAt: data.lastActivityAt.present
          ? data.lastActivityAt.value
          : this.lastActivityAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkspaceActivityTableData(')
          ..write('workspaceId: $workspaceId, ')
          ..write('lastActivityAt: $lastActivityAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(workspaceId, lastActivityAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceActivityTableData &&
          other.workspaceId == this.workspaceId &&
          other.lastActivityAt == this.lastActivityAt);
}

class WorkspaceActivityTableCompanion
    extends UpdateCompanion<WorkspaceActivityTableData> {
  final Value<String> workspaceId;
  final Value<DateTime> lastActivityAt;
  final Value<int> rowid;
  const WorkspaceActivityTableCompanion({
    this.workspaceId = const Value.absent(),
    this.lastActivityAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkspaceActivityTableCompanion.insert({
    required String workspaceId,
    required DateTime lastActivityAt,
    this.rowid = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       lastActivityAt = Value(lastActivityAt);
  static Insertable<WorkspaceActivityTableData> custom({
    Expression<String>? workspaceId,
    Expression<DateTime>? lastActivityAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (lastActivityAt != null) 'last_activity_at': lastActivityAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkspaceActivityTableCompanion copyWith({
    Value<String>? workspaceId,
    Value<DateTime>? lastActivityAt,
    Value<int>? rowid,
  }) {
    return WorkspaceActivityTableCompanion(
      workspaceId: workspaceId ?? this.workspaceId,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (lastActivityAt.present) {
      map['last_activity_at'] = Variable<DateTime>(lastActivityAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkspaceActivityTableCompanion(')
          ..write('workspaceId: $workspaceId, ')
          ..write('lastActivityAt: $lastActivityAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AleraDatabase extends GeneratedDatabase {
  _$AleraDatabase(QueryExecutor e) : super(e);
  $AleraDatabaseManager get managers => $AleraDatabaseManager(this);
  late final $ProjectsTableTable projectsTable = $ProjectsTableTable(this);
  late final $WorkspacesTableTable workspacesTable = $WorkspacesTableTable(
    this,
  );
  late final $WorkspaceTabsTableTable workspaceTabsTable =
      $WorkspaceTabsTableTable(this);
  late final $WorkbenchLayoutsTableTable workbenchLayoutsTable =
      $WorkbenchLayoutsTableTable(this);
  late final $WorkbenchViewPrefsTableTable workbenchViewPrefsTable =
      $WorkbenchViewPrefsTableTable(this);
  late final $AppSettingsTableTable appSettingsTable = $AppSettingsTableTable(
    this,
  );
  late final $ProjectConfigsTableTable projectConfigsTable =
      $ProjectConfigsTableTable(this);
  late final $AppWindowStateTableTable appWindowStateTable =
      $AppWindowStateTableTable(this);
  late final $WorkspaceActivityTableTable workspaceActivityTable =
      $WorkspaceActivityTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    projectsTable,
    workspacesTable,
    workspaceTabsTable,
    workbenchLayoutsTable,
    workbenchViewPrefsTable,
    appSettingsTable,
    projectConfigsTable,
    appWindowStateTable,
    workspaceActivityTable,
  ];
}

typedef $$ProjectsTableTableCreateCompanionBuilder =
    ProjectsTableCompanion Function({
      required String id,
      required String name,
      required String repoPath,
      required DateTime createdAt,
      required DateTime updatedAt,
      required String kind,
      Value<int> rowid,
    });
typedef $$ProjectsTableTableUpdateCompanionBuilder =
    ProjectsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> repoPath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> kind,
      Value<int> rowid,
    });

class $$ProjectsTableTableFilterComposer
    extends Composer<_$AleraDatabase, $ProjectsTableTable> {
  $$ProjectsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repoPath => $composableBuilder(
    column: $table.repoPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectsTableTableOrderingComposer
    extends Composer<_$AleraDatabase, $ProjectsTableTable> {
  $$ProjectsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repoPath => $composableBuilder(
    column: $table.repoPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectsTableTableAnnotationComposer
    extends Composer<_$AleraDatabase, $ProjectsTableTable> {
  $$ProjectsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get repoPath =>
      $composableBuilder(column: $table.repoPath, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);
}

class $$ProjectsTableTableTableManager
    extends
        RootTableManager<
          _$AleraDatabase,
          $ProjectsTableTable,
          ProjectsTableData,
          $$ProjectsTableTableFilterComposer,
          $$ProjectsTableTableOrderingComposer,
          $$ProjectsTableTableAnnotationComposer,
          $$ProjectsTableTableCreateCompanionBuilder,
          $$ProjectsTableTableUpdateCompanionBuilder,
          (
            ProjectsTableData,
            BaseReferences<
              _$AleraDatabase,
              $ProjectsTableTable,
              ProjectsTableData
            >,
          ),
          ProjectsTableData,
          PrefetchHooks Function()
        > {
  $$ProjectsTableTableTableManager(
    _$AleraDatabase db,
    $ProjectsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> repoPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsTableCompanion(
                id: id,
                name: name,
                repoPath: repoPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                kind: kind,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String repoPath,
                required DateTime createdAt,
                required DateTime updatedAt,
                required String kind,
                Value<int> rowid = const Value.absent(),
              }) => ProjectsTableCompanion.insert(
                id: id,
                name: name,
                repoPath: repoPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                kind: kind,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProjectsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AleraDatabase,
      $ProjectsTableTable,
      ProjectsTableData,
      $$ProjectsTableTableFilterComposer,
      $$ProjectsTableTableOrderingComposer,
      $$ProjectsTableTableAnnotationComposer,
      $$ProjectsTableTableCreateCompanionBuilder,
      $$ProjectsTableTableUpdateCompanionBuilder,
      (
        ProjectsTableData,
        BaseReferences<_$AleraDatabase, $ProjectsTableTable, ProjectsTableData>,
      ),
      ProjectsTableData,
      PrefetchHooks Function()
    >;
typedef $$WorkspacesTableTableCreateCompanionBuilder =
    WorkspacesTableCompanion Function({
      required String id,
      required String projectId,
      required String name,
      Value<String?> branch,
      required String path,
      required DateTime createdAt,
      required DateTime updatedAt,
      required String kind,
      required String status,
      Value<String?> sourceBranch,
      Value<bool> reusesExistingBranch,
      Value<bool> isPinned,
      Value<int> rowid,
    });
typedef $$WorkspacesTableTableUpdateCompanionBuilder =
    WorkspacesTableCompanion Function({
      Value<String> id,
      Value<String> projectId,
      Value<String> name,
      Value<String?> branch,
      Value<String> path,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> kind,
      Value<String> status,
      Value<String?> sourceBranch,
      Value<bool> reusesExistingBranch,
      Value<bool> isPinned,
      Value<int> rowid,
    });

class $$WorkspacesTableTableFilterComposer
    extends Composer<_$AleraDatabase, $WorkspacesTableTable> {
  $$WorkspacesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branch => $composableBuilder(
    column: $table.branch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceBranch => $composableBuilder(
    column: $table.sourceBranch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reusesExistingBranch => $composableBuilder(
    column: $table.reusesExistingBranch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkspacesTableTableOrderingComposer
    extends Composer<_$AleraDatabase, $WorkspacesTableTable> {
  $$WorkspacesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branch => $composableBuilder(
    column: $table.branch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceBranch => $composableBuilder(
    column: $table.sourceBranch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reusesExistingBranch => $composableBuilder(
    column: $table.reusesExistingBranch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkspacesTableTableAnnotationComposer
    extends Composer<_$AleraDatabase, $WorkspacesTableTable> {
  $$WorkspacesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get branch =>
      $composableBuilder(column: $table.branch, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get sourceBranch => $composableBuilder(
    column: $table.sourceBranch,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get reusesExistingBranch => $composableBuilder(
    column: $table.reusesExistingBranch,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);
}

class $$WorkspacesTableTableTableManager
    extends
        RootTableManager<
          _$AleraDatabase,
          $WorkspacesTableTable,
          WorkspacesTableData,
          $$WorkspacesTableTableFilterComposer,
          $$WorkspacesTableTableOrderingComposer,
          $$WorkspacesTableTableAnnotationComposer,
          $$WorkspacesTableTableCreateCompanionBuilder,
          $$WorkspacesTableTableUpdateCompanionBuilder,
          (
            WorkspacesTableData,
            BaseReferences<
              _$AleraDatabase,
              $WorkspacesTableTable,
              WorkspacesTableData
            >,
          ),
          WorkspacesTableData,
          PrefetchHooks Function()
        > {
  $$WorkspacesTableTableTableManager(
    _$AleraDatabase db,
    $WorkspacesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkspacesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkspacesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkspacesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> branch = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> sourceBranch = const Value.absent(),
                Value<bool> reusesExistingBranch = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkspacesTableCompanion(
                id: id,
                projectId: projectId,
                name: name,
                branch: branch,
                path: path,
                createdAt: createdAt,
                updatedAt: updatedAt,
                kind: kind,
                status: status,
                sourceBranch: sourceBranch,
                reusesExistingBranch: reusesExistingBranch,
                isPinned: isPinned,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String projectId,
                required String name,
                Value<String?> branch = const Value.absent(),
                required String path,
                required DateTime createdAt,
                required DateTime updatedAt,
                required String kind,
                required String status,
                Value<String?> sourceBranch = const Value.absent(),
                Value<bool> reusesExistingBranch = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkspacesTableCompanion.insert(
                id: id,
                projectId: projectId,
                name: name,
                branch: branch,
                path: path,
                createdAt: createdAt,
                updatedAt: updatedAt,
                kind: kind,
                status: status,
                sourceBranch: sourceBranch,
                reusesExistingBranch: reusesExistingBranch,
                isPinned: isPinned,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkspacesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AleraDatabase,
      $WorkspacesTableTable,
      WorkspacesTableData,
      $$WorkspacesTableTableFilterComposer,
      $$WorkspacesTableTableOrderingComposer,
      $$WorkspacesTableTableAnnotationComposer,
      $$WorkspacesTableTableCreateCompanionBuilder,
      $$WorkspacesTableTableUpdateCompanionBuilder,
      (
        WorkspacesTableData,
        BaseReferences<
          _$AleraDatabase,
          $WorkspacesTableTable,
          WorkspacesTableData
        >,
      ),
      WorkspacesTableData,
      PrefetchHooks Function()
    >;
typedef $$WorkspaceTabsTableTableCreateCompanionBuilder =
    WorkspaceTabsTableCompanion Function({
      required String id,
      required String workspaceId,
      required String kind,
      required String title,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String> payloadJson,
      Value<int> rowid,
    });
typedef $$WorkspaceTabsTableTableUpdateCompanionBuilder =
    WorkspaceTabsTableCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> kind,
      Value<String> title,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> payloadJson,
      Value<int> rowid,
    });

class $$WorkspaceTabsTableTableFilterComposer
    extends Composer<_$AleraDatabase, $WorkspaceTabsTableTable> {
  $$WorkspaceTabsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkspaceTabsTableTableOrderingComposer
    extends Composer<_$AleraDatabase, $WorkspaceTabsTableTable> {
  $$WorkspaceTabsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkspaceTabsTableTableAnnotationComposer
    extends Composer<_$AleraDatabase, $WorkspaceTabsTableTable> {
  $$WorkspaceTabsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$WorkspaceTabsTableTableTableManager
    extends
        RootTableManager<
          _$AleraDatabase,
          $WorkspaceTabsTableTable,
          WorkspaceTabsTableData,
          $$WorkspaceTabsTableTableFilterComposer,
          $$WorkspaceTabsTableTableOrderingComposer,
          $$WorkspaceTabsTableTableAnnotationComposer,
          $$WorkspaceTabsTableTableCreateCompanionBuilder,
          $$WorkspaceTabsTableTableUpdateCompanionBuilder,
          (
            WorkspaceTabsTableData,
            BaseReferences<
              _$AleraDatabase,
              $WorkspaceTabsTableTable,
              WorkspaceTabsTableData
            >,
          ),
          WorkspaceTabsTableData,
          PrefetchHooks Function()
        > {
  $$WorkspaceTabsTableTableTableManager(
    _$AleraDatabase db,
    $WorkspaceTabsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkspaceTabsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkspaceTabsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkspaceTabsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkspaceTabsTableCompanion(
                id: id,
                workspaceId: workspaceId,
                kind: kind,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String kind,
                required String title,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkspaceTabsTableCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                kind: kind,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkspaceTabsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AleraDatabase,
      $WorkspaceTabsTableTable,
      WorkspaceTabsTableData,
      $$WorkspaceTabsTableTableFilterComposer,
      $$WorkspaceTabsTableTableOrderingComposer,
      $$WorkspaceTabsTableTableAnnotationComposer,
      $$WorkspaceTabsTableTableCreateCompanionBuilder,
      $$WorkspaceTabsTableTableUpdateCompanionBuilder,
      (
        WorkspaceTabsTableData,
        BaseReferences<
          _$AleraDatabase,
          $WorkspaceTabsTableTable,
          WorkspaceTabsTableData
        >,
      ),
      WorkspaceTabsTableData,
      PrefetchHooks Function()
    >;
typedef $$WorkbenchLayoutsTableTableCreateCompanionBuilder =
    WorkbenchLayoutsTableCompanion Function({
      required String workspaceId,
      required String dataJson,
      Value<int> rowid,
    });
typedef $$WorkbenchLayoutsTableTableUpdateCompanionBuilder =
    WorkbenchLayoutsTableCompanion Function({
      Value<String> workspaceId,
      Value<String> dataJson,
      Value<int> rowid,
    });

class $$WorkbenchLayoutsTableTableFilterComposer
    extends Composer<_$AleraDatabase, $WorkbenchLayoutsTableTable> {
  $$WorkbenchLayoutsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkbenchLayoutsTableTableOrderingComposer
    extends Composer<_$AleraDatabase, $WorkbenchLayoutsTableTable> {
  $$WorkbenchLayoutsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkbenchLayoutsTableTableAnnotationComposer
    extends Composer<_$AleraDatabase, $WorkbenchLayoutsTableTable> {
  $$WorkbenchLayoutsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);
}

class $$WorkbenchLayoutsTableTableTableManager
    extends
        RootTableManager<
          _$AleraDatabase,
          $WorkbenchLayoutsTableTable,
          WorkbenchLayoutsTableData,
          $$WorkbenchLayoutsTableTableFilterComposer,
          $$WorkbenchLayoutsTableTableOrderingComposer,
          $$WorkbenchLayoutsTableTableAnnotationComposer,
          $$WorkbenchLayoutsTableTableCreateCompanionBuilder,
          $$WorkbenchLayoutsTableTableUpdateCompanionBuilder,
          (
            WorkbenchLayoutsTableData,
            BaseReferences<
              _$AleraDatabase,
              $WorkbenchLayoutsTableTable,
              WorkbenchLayoutsTableData
            >,
          ),
          WorkbenchLayoutsTableData,
          PrefetchHooks Function()
        > {
  $$WorkbenchLayoutsTableTableTableManager(
    _$AleraDatabase db,
    $WorkbenchLayoutsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkbenchLayoutsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$WorkbenchLayoutsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$WorkbenchLayoutsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> workspaceId = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkbenchLayoutsTableCompanion(
                workspaceId: workspaceId,
                dataJson: dataJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workspaceId,
                required String dataJson,
                Value<int> rowid = const Value.absent(),
              }) => WorkbenchLayoutsTableCompanion.insert(
                workspaceId: workspaceId,
                dataJson: dataJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkbenchLayoutsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AleraDatabase,
      $WorkbenchLayoutsTableTable,
      WorkbenchLayoutsTableData,
      $$WorkbenchLayoutsTableTableFilterComposer,
      $$WorkbenchLayoutsTableTableOrderingComposer,
      $$WorkbenchLayoutsTableTableAnnotationComposer,
      $$WorkbenchLayoutsTableTableCreateCompanionBuilder,
      $$WorkbenchLayoutsTableTableUpdateCompanionBuilder,
      (
        WorkbenchLayoutsTableData,
        BaseReferences<
          _$AleraDatabase,
          $WorkbenchLayoutsTableTable,
          WorkbenchLayoutsTableData
        >,
      ),
      WorkbenchLayoutsTableData,
      PrefetchHooks Function()
    >;
typedef $$WorkbenchViewPrefsTableTableCreateCompanionBuilder =
    WorkbenchViewPrefsTableCompanion Function({
      Value<int> id,
      required String dataJson,
    });
typedef $$WorkbenchViewPrefsTableTableUpdateCompanionBuilder =
    WorkbenchViewPrefsTableCompanion Function({
      Value<int> id,
      Value<String> dataJson,
    });

class $$WorkbenchViewPrefsTableTableFilterComposer
    extends Composer<_$AleraDatabase, $WorkbenchViewPrefsTableTable> {
  $$WorkbenchViewPrefsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkbenchViewPrefsTableTableOrderingComposer
    extends Composer<_$AleraDatabase, $WorkbenchViewPrefsTableTable> {
  $$WorkbenchViewPrefsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkbenchViewPrefsTableTableAnnotationComposer
    extends Composer<_$AleraDatabase, $WorkbenchViewPrefsTableTable> {
  $$WorkbenchViewPrefsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);
}

class $$WorkbenchViewPrefsTableTableTableManager
    extends
        RootTableManager<
          _$AleraDatabase,
          $WorkbenchViewPrefsTableTable,
          WorkbenchViewPrefsTableData,
          $$WorkbenchViewPrefsTableTableFilterComposer,
          $$WorkbenchViewPrefsTableTableOrderingComposer,
          $$WorkbenchViewPrefsTableTableAnnotationComposer,
          $$WorkbenchViewPrefsTableTableCreateCompanionBuilder,
          $$WorkbenchViewPrefsTableTableUpdateCompanionBuilder,
          (
            WorkbenchViewPrefsTableData,
            BaseReferences<
              _$AleraDatabase,
              $WorkbenchViewPrefsTableTable,
              WorkbenchViewPrefsTableData
            >,
          ),
          WorkbenchViewPrefsTableData,
          PrefetchHooks Function()
        > {
  $$WorkbenchViewPrefsTableTableTableManager(
    _$AleraDatabase db,
    $WorkbenchViewPrefsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkbenchViewPrefsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$WorkbenchViewPrefsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$WorkbenchViewPrefsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
              }) =>
                  WorkbenchViewPrefsTableCompanion(id: id, dataJson: dataJson),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String dataJson,
              }) => WorkbenchViewPrefsTableCompanion.insert(
                id: id,
                dataJson: dataJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkbenchViewPrefsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AleraDatabase,
      $WorkbenchViewPrefsTableTable,
      WorkbenchViewPrefsTableData,
      $$WorkbenchViewPrefsTableTableFilterComposer,
      $$WorkbenchViewPrefsTableTableOrderingComposer,
      $$WorkbenchViewPrefsTableTableAnnotationComposer,
      $$WorkbenchViewPrefsTableTableCreateCompanionBuilder,
      $$WorkbenchViewPrefsTableTableUpdateCompanionBuilder,
      (
        WorkbenchViewPrefsTableData,
        BaseReferences<
          _$AleraDatabase,
          $WorkbenchViewPrefsTableTable,
          WorkbenchViewPrefsTableData
        >,
      ),
      WorkbenchViewPrefsTableData,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableTableCreateCompanionBuilder =
    AppSettingsTableCompanion Function({
      Value<int> id,
      required String dataJson,
    });
typedef $$AppSettingsTableTableUpdateCompanionBuilder =
    AppSettingsTableCompanion Function({Value<int> id, Value<String> dataJson});

class $$AppSettingsTableTableFilterComposer
    extends Composer<_$AleraDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableTableOrderingComposer
    extends Composer<_$AleraDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableTableAnnotationComposer
    extends Composer<_$AleraDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);
}

class $$AppSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AleraDatabase,
          $AppSettingsTableTable,
          AppSettingsTableData,
          $$AppSettingsTableTableFilterComposer,
          $$AppSettingsTableTableOrderingComposer,
          $$AppSettingsTableTableAnnotationComposer,
          $$AppSettingsTableTableCreateCompanionBuilder,
          $$AppSettingsTableTableUpdateCompanionBuilder,
          (
            AppSettingsTableData,
            BaseReferences<
              _$AleraDatabase,
              $AppSettingsTableTable,
              AppSettingsTableData
            >,
          ),
          AppSettingsTableData,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableTableManager(
    _$AleraDatabase db,
    $AppSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
              }) => AppSettingsTableCompanion(id: id, dataJson: dataJson),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String dataJson,
              }) =>
                  AppSettingsTableCompanion.insert(id: id, dataJson: dataJson),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AleraDatabase,
      $AppSettingsTableTable,
      AppSettingsTableData,
      $$AppSettingsTableTableFilterComposer,
      $$AppSettingsTableTableOrderingComposer,
      $$AppSettingsTableTableAnnotationComposer,
      $$AppSettingsTableTableCreateCompanionBuilder,
      $$AppSettingsTableTableUpdateCompanionBuilder,
      (
        AppSettingsTableData,
        BaseReferences<
          _$AleraDatabase,
          $AppSettingsTableTable,
          AppSettingsTableData
        >,
      ),
      AppSettingsTableData,
      PrefetchHooks Function()
    >;
typedef $$ProjectConfigsTableTableCreateCompanionBuilder =
    ProjectConfigsTableCompanion Function({
      required String projectId,
      required String dataJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ProjectConfigsTableTableUpdateCompanionBuilder =
    ProjectConfigsTableCompanion Function({
      Value<String> projectId,
      Value<String> dataJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ProjectConfigsTableTableFilterComposer
    extends Composer<_$AleraDatabase, $ProjectConfigsTableTable> {
  $$ProjectConfigsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectConfigsTableTableOrderingComposer
    extends Composer<_$AleraDatabase, $ProjectConfigsTableTable> {
  $$ProjectConfigsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectConfigsTableTableAnnotationComposer
    extends Composer<_$AleraDatabase, $ProjectConfigsTableTable> {
  $$ProjectConfigsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProjectConfigsTableTableTableManager
    extends
        RootTableManager<
          _$AleraDatabase,
          $ProjectConfigsTableTable,
          ProjectConfigsTableData,
          $$ProjectConfigsTableTableFilterComposer,
          $$ProjectConfigsTableTableOrderingComposer,
          $$ProjectConfigsTableTableAnnotationComposer,
          $$ProjectConfigsTableTableCreateCompanionBuilder,
          $$ProjectConfigsTableTableUpdateCompanionBuilder,
          (
            ProjectConfigsTableData,
            BaseReferences<
              _$AleraDatabase,
              $ProjectConfigsTableTable,
              ProjectConfigsTableData
            >,
          ),
          ProjectConfigsTableData,
          PrefetchHooks Function()
        > {
  $$ProjectConfigsTableTableTableManager(
    _$AleraDatabase db,
    $ProjectConfigsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectConfigsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectConfigsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProjectConfigsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> projectId = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectConfigsTableCompanion(
                projectId: projectId,
                dataJson: dataJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String projectId,
                required String dataJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProjectConfigsTableCompanion.insert(
                projectId: projectId,
                dataJson: dataJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProjectConfigsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AleraDatabase,
      $ProjectConfigsTableTable,
      ProjectConfigsTableData,
      $$ProjectConfigsTableTableFilterComposer,
      $$ProjectConfigsTableTableOrderingComposer,
      $$ProjectConfigsTableTableAnnotationComposer,
      $$ProjectConfigsTableTableCreateCompanionBuilder,
      $$ProjectConfigsTableTableUpdateCompanionBuilder,
      (
        ProjectConfigsTableData,
        BaseReferences<
          _$AleraDatabase,
          $ProjectConfigsTableTable,
          ProjectConfigsTableData
        >,
      ),
      ProjectConfigsTableData,
      PrefetchHooks Function()
    >;
typedef $$AppWindowStateTableTableCreateCompanionBuilder =
    AppWindowStateTableCompanion Function({
      Value<int> id,
      required String dataJson,
      required DateTime updatedAt,
    });
typedef $$AppWindowStateTableTableUpdateCompanionBuilder =
    AppWindowStateTableCompanion Function({
      Value<int> id,
      Value<String> dataJson,
      Value<DateTime> updatedAt,
    });

class $$AppWindowStateTableTableFilterComposer
    extends Composer<_$AleraDatabase, $AppWindowStateTableTable> {
  $$AppWindowStateTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppWindowStateTableTableOrderingComposer
    extends Composer<_$AleraDatabase, $AppWindowStateTableTable> {
  $$AppWindowStateTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppWindowStateTableTableAnnotationComposer
    extends Composer<_$AleraDatabase, $AppWindowStateTableTable> {
  $$AppWindowStateTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppWindowStateTableTableTableManager
    extends
        RootTableManager<
          _$AleraDatabase,
          $AppWindowStateTableTable,
          AppWindowStateTableData,
          $$AppWindowStateTableTableFilterComposer,
          $$AppWindowStateTableTableOrderingComposer,
          $$AppWindowStateTableTableAnnotationComposer,
          $$AppWindowStateTableTableCreateCompanionBuilder,
          $$AppWindowStateTableTableUpdateCompanionBuilder,
          (
            AppWindowStateTableData,
            BaseReferences<
              _$AleraDatabase,
              $AppWindowStateTableTable,
              AppWindowStateTableData
            >,
          ),
          AppWindowStateTableData,
          PrefetchHooks Function()
        > {
  $$AppWindowStateTableTableTableManager(
    _$AleraDatabase db,
    $AppWindowStateTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppWindowStateTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppWindowStateTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AppWindowStateTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => AppWindowStateTableCompanion(
                id: id,
                dataJson: dataJson,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String dataJson,
                required DateTime updatedAt,
              }) => AppWindowStateTableCompanion.insert(
                id: id,
                dataJson: dataJson,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppWindowStateTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AleraDatabase,
      $AppWindowStateTableTable,
      AppWindowStateTableData,
      $$AppWindowStateTableTableFilterComposer,
      $$AppWindowStateTableTableOrderingComposer,
      $$AppWindowStateTableTableAnnotationComposer,
      $$AppWindowStateTableTableCreateCompanionBuilder,
      $$AppWindowStateTableTableUpdateCompanionBuilder,
      (
        AppWindowStateTableData,
        BaseReferences<
          _$AleraDatabase,
          $AppWindowStateTableTable,
          AppWindowStateTableData
        >,
      ),
      AppWindowStateTableData,
      PrefetchHooks Function()
    >;
typedef $$WorkspaceActivityTableTableCreateCompanionBuilder =
    WorkspaceActivityTableCompanion Function({
      required String workspaceId,
      required DateTime lastActivityAt,
      Value<int> rowid,
    });
typedef $$WorkspaceActivityTableTableUpdateCompanionBuilder =
    WorkspaceActivityTableCompanion Function({
      Value<String> workspaceId,
      Value<DateTime> lastActivityAt,
      Value<int> rowid,
    });

class $$WorkspaceActivityTableTableFilterComposer
    extends Composer<_$AleraDatabase, $WorkspaceActivityTableTable> {
  $$WorkspaceActivityTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastActivityAt => $composableBuilder(
    column: $table.lastActivityAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkspaceActivityTableTableOrderingComposer
    extends Composer<_$AleraDatabase, $WorkspaceActivityTableTable> {
  $$WorkspaceActivityTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastActivityAt => $composableBuilder(
    column: $table.lastActivityAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkspaceActivityTableTableAnnotationComposer
    extends Composer<_$AleraDatabase, $WorkspaceActivityTableTable> {
  $$WorkspaceActivityTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastActivityAt => $composableBuilder(
    column: $table.lastActivityAt,
    builder: (column) => column,
  );
}

class $$WorkspaceActivityTableTableTableManager
    extends
        RootTableManager<
          _$AleraDatabase,
          $WorkspaceActivityTableTable,
          WorkspaceActivityTableData,
          $$WorkspaceActivityTableTableFilterComposer,
          $$WorkspaceActivityTableTableOrderingComposer,
          $$WorkspaceActivityTableTableAnnotationComposer,
          $$WorkspaceActivityTableTableCreateCompanionBuilder,
          $$WorkspaceActivityTableTableUpdateCompanionBuilder,
          (
            WorkspaceActivityTableData,
            BaseReferences<
              _$AleraDatabase,
              $WorkspaceActivityTableTable,
              WorkspaceActivityTableData
            >,
          ),
          WorkspaceActivityTableData,
          PrefetchHooks Function()
        > {
  $$WorkspaceActivityTableTableTableManager(
    _$AleraDatabase db,
    $WorkspaceActivityTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkspaceActivityTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$WorkspaceActivityTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$WorkspaceActivityTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> workspaceId = const Value.absent(),
                Value<DateTime> lastActivityAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkspaceActivityTableCompanion(
                workspaceId: workspaceId,
                lastActivityAt: lastActivityAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workspaceId,
                required DateTime lastActivityAt,
                Value<int> rowid = const Value.absent(),
              }) => WorkspaceActivityTableCompanion.insert(
                workspaceId: workspaceId,
                lastActivityAt: lastActivityAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkspaceActivityTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AleraDatabase,
      $WorkspaceActivityTableTable,
      WorkspaceActivityTableData,
      $$WorkspaceActivityTableTableFilterComposer,
      $$WorkspaceActivityTableTableOrderingComposer,
      $$WorkspaceActivityTableTableAnnotationComposer,
      $$WorkspaceActivityTableTableCreateCompanionBuilder,
      $$WorkspaceActivityTableTableUpdateCompanionBuilder,
      (
        WorkspaceActivityTableData,
        BaseReferences<
          _$AleraDatabase,
          $WorkspaceActivityTableTable,
          WorkspaceActivityTableData
        >,
      ),
      WorkspaceActivityTableData,
      PrefetchHooks Function()
    >;

class $AleraDatabaseManager {
  final _$AleraDatabase _db;
  $AleraDatabaseManager(this._db);
  $$ProjectsTableTableTableManager get projectsTable =>
      $$ProjectsTableTableTableManager(_db, _db.projectsTable);
  $$WorkspacesTableTableTableManager get workspacesTable =>
      $$WorkspacesTableTableTableManager(_db, _db.workspacesTable);
  $$WorkspaceTabsTableTableTableManager get workspaceTabsTable =>
      $$WorkspaceTabsTableTableTableManager(_db, _db.workspaceTabsTable);
  $$WorkbenchLayoutsTableTableTableManager get workbenchLayoutsTable =>
      $$WorkbenchLayoutsTableTableTableManager(_db, _db.workbenchLayoutsTable);
  $$WorkbenchViewPrefsTableTableTableManager get workbenchViewPrefsTable =>
      $$WorkbenchViewPrefsTableTableTableManager(
        _db,
        _db.workbenchViewPrefsTable,
      );
  $$AppSettingsTableTableTableManager get appSettingsTable =>
      $$AppSettingsTableTableTableManager(_db, _db.appSettingsTable);
  $$ProjectConfigsTableTableTableManager get projectConfigsTable =>
      $$ProjectConfigsTableTableTableManager(_db, _db.projectConfigsTable);
  $$AppWindowStateTableTableTableManager get appWindowStateTable =>
      $$AppWindowStateTableTableTableManager(_db, _db.appWindowStateTable);
  $$WorkspaceActivityTableTableTableManager get workspaceActivityTable =>
      $$WorkspaceActivityTableTableTableManager(
        _db,
        _db.workspaceActivityTable,
      );
}
