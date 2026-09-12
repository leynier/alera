// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_control_commit_draft.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The commit message being typed for a workspace. Kept alive so switching
/// panels or opening a diff does not throw the message away.

@ProviderFor(SourceControlCommitDraft)
final sourceControlCommitDraftProvider = SourceControlCommitDraftFamily._();

/// The commit message being typed for a workspace. Kept alive so switching
/// panels or opening a diff does not throw the message away.
final class SourceControlCommitDraftProvider
    extends $NotifierProvider<SourceControlCommitDraft, String> {
  /// The commit message being typed for a workspace. Kept alive so switching
  /// panels or opening a diff does not throw the message away.
  SourceControlCommitDraftProvider._({
    required SourceControlCommitDraftFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'sourceControlCommitDraftProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sourceControlCommitDraftHash();

  @override
  String toString() {
    return r'sourceControlCommitDraftProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SourceControlCommitDraft create() => SourceControlCommitDraft();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SourceControlCommitDraftProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sourceControlCommitDraftHash() =>
    r'4b2abdb740a5802467a7d5bfbab92918dfda0601';

/// The commit message being typed for a workspace. Kept alive so switching
/// panels or opening a diff does not throw the message away.

final class SourceControlCommitDraftFamily extends $Family
    with
        $ClassFamilyOverride<
          SourceControlCommitDraft,
          String,
          String,
          String,
          (String, String)
        > {
  SourceControlCommitDraftFamily._()
    : super(
        retry: null,
        name: r'sourceControlCommitDraftProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The commit message being typed for a workspace. Kept alive so switching
  /// panels or opening a diff does not throw the message away.

  SourceControlCommitDraftProvider call(String hostId, String workspaceId) =>
      SourceControlCommitDraftProvider._(
        argument: (hostId, workspaceId),
        from: this,
      );

  @override
  String toString() => r'sourceControlCommitDraftProvider';
}

/// The commit message being typed for a workspace. Kept alive so switching
/// panels or opening a diff does not throw the message away.

abstract class _$SourceControlCommitDraft extends $Notifier<String> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  String build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
