// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'git_remote_identity.dart';

class GitRemoteIdentityMapper extends ClassMapperBase<GitRemoteIdentity> {
  GitRemoteIdentityMapper._();

  static GitRemoteIdentityMapper? _instance;
  static GitRemoteIdentityMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GitRemoteIdentityMapper._());
      GitHostingProviderMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GitRemoteIdentity';

  static GitHostingProvider _$provider(GitRemoteIdentity v) => v.provider;
  static const Field<GitRemoteIdentity, GitHostingProvider> _f$provider = Field(
    'provider',
    _$provider,
  );
  static String _$host(GitRemoteIdentity v) => v.host;
  static const Field<GitRemoteIdentity, String> _f$host = Field('host', _$host);
  static String _$owner(GitRemoteIdentity v) => v.owner;
  static const Field<GitRemoteIdentity, String> _f$owner = Field(
    'owner',
    _$owner,
  );
  static String _$repo(GitRemoteIdentity v) => v.repo;
  static const Field<GitRemoteIdentity, String> _f$repo = Field('repo', _$repo);
  static String? _$project(GitRemoteIdentity v) => v.project;
  static const Field<GitRemoteIdentity, String> _f$project = Field(
    'project',
    _$project,
    opt: true,
  );

  @override
  final MappableFields<GitRemoteIdentity> fields = const {
    #provider: _f$provider,
    #host: _f$host,
    #owner: _f$owner,
    #repo: _f$repo,
    #project: _f$project,
  };

  static GitRemoteIdentity _instantiate(DecodingData data) {
    return GitRemoteIdentity(
      provider: data.dec(_f$provider),
      host: data.dec(_f$host),
      owner: data.dec(_f$owner),
      repo: data.dec(_f$repo),
      project: data.dec(_f$project),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GitRemoteIdentity fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GitRemoteIdentity>(map);
  }

  static GitRemoteIdentity fromJson(String json) {
    return ensureInitialized().decodeJson<GitRemoteIdentity>(json);
  }
}

mixin GitRemoteIdentityMappable {
  String toJson() {
    return GitRemoteIdentityMapper.ensureInitialized()
        .encodeJson<GitRemoteIdentity>(this as GitRemoteIdentity);
  }

  Map<String, dynamic> toMap() {
    return GitRemoteIdentityMapper.ensureInitialized()
        .encodeMap<GitRemoteIdentity>(this as GitRemoteIdentity);
  }

  GitRemoteIdentityCopyWith<
    GitRemoteIdentity,
    GitRemoteIdentity,
    GitRemoteIdentity
  >
  get copyWith =>
      _GitRemoteIdentityCopyWithImpl<GitRemoteIdentity, GitRemoteIdentity>(
        this as GitRemoteIdentity,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return GitRemoteIdentityMapper.ensureInitialized().stringifyValue(
      this as GitRemoteIdentity,
    );
  }

  @override
  bool operator ==(Object other) {
    return GitRemoteIdentityMapper.ensureInitialized().equalsValue(
      this as GitRemoteIdentity,
      other,
    );
  }

  @override
  int get hashCode {
    return GitRemoteIdentityMapper.ensureInitialized().hashValue(
      this as GitRemoteIdentity,
    );
  }
}

extension GitRemoteIdentityValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GitRemoteIdentity, $Out> {
  GitRemoteIdentityCopyWith<$R, GitRemoteIdentity, $Out>
  get $asGitRemoteIdentity => $base.as(
    (v, t, t2) => _GitRemoteIdentityCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class GitRemoteIdentityCopyWith<
  $R,
  $In extends GitRemoteIdentity,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    GitHostingProvider? provider,
    String? host,
    String? owner,
    String? repo,
    String? project,
  });
  GitRemoteIdentityCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _GitRemoteIdentityCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GitRemoteIdentity, $Out>
    implements GitRemoteIdentityCopyWith<$R, GitRemoteIdentity, $Out> {
  _GitRemoteIdentityCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GitRemoteIdentity> $mapper =
      GitRemoteIdentityMapper.ensureInitialized();
  @override
  $R call({
    GitHostingProvider? provider,
    String? host,
    String? owner,
    String? repo,
    Object? project = $none,
  }) => $apply(
    FieldCopyWithData({
      if (provider != null) #provider: provider,
      if (host != null) #host: host,
      if (owner != null) #owner: owner,
      if (repo != null) #repo: repo,
      if (project != $none) #project: project,
    }),
  );
  @override
  GitRemoteIdentity $make(CopyWithData data) => GitRemoteIdentity(
    provider: data.get(#provider, or: $value.provider),
    host: data.get(#host, or: $value.host),
    owner: data.get(#owner, or: $value.owner),
    repo: data.get(#repo, or: $value.repo),
    project: data.get(#project, or: $value.project),
  );

  @override
  GitRemoteIdentityCopyWith<$R2, GitRemoteIdentity, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GitRemoteIdentityCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
