// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_control_actions_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Runs source control writes for one workspace and holds the one in flight,
/// so every control can disable itself while the runtime works.
///
/// Kept alive because a fetch or a push runs for minutes: the Source Control
/// panel is the only watcher, so an autoDispose family would drop the write
/// the moment the user switches to Explorer, re-enabling every control and
/// throwing away the snapshot the runtime is about to answer with.

@ProviderFor(SourceControlActionsController)
final sourceControlActionsControllerProvider =
    SourceControlActionsControllerFamily._();

/// Runs source control writes for one workspace and holds the one in flight,
/// so every control can disable itself while the runtime works.
///
/// Kept alive because a fetch or a push runs for minutes: the Source Control
/// panel is the only watcher, so an autoDispose family would drop the write
/// the moment the user switches to Explorer, re-enabling every control and
/// throwing away the snapshot the runtime is about to answer with.
final class SourceControlActionsControllerProvider
    extends
        $NotifierProvider<
          SourceControlActionsController,
          MobileGitWriteAction?
        > {
  /// Runs source control writes for one workspace and holds the one in flight,
  /// so every control can disable itself while the runtime works.
  ///
  /// Kept alive because a fetch or a push runs for minutes: the Source Control
  /// panel is the only watcher, so an autoDispose family would drop the write
  /// the moment the user switches to Explorer, re-enabling every control and
  /// throwing away the snapshot the runtime is about to answer with.
  SourceControlActionsControllerProvider._({
    required SourceControlActionsControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'sourceControlActionsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sourceControlActionsControllerHash();

  @override
  String toString() {
    return r'sourceControlActionsControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SourceControlActionsController create() => SourceControlActionsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileGitWriteAction? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileGitWriteAction?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SourceControlActionsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sourceControlActionsControllerHash() =>
    r'fd3fbb56d6196b7ab3e3804698adbc3beb52b843';

/// Runs source control writes for one workspace and holds the one in flight,
/// so every control can disable itself while the runtime works.
///
/// Kept alive because a fetch or a push runs for minutes: the Source Control
/// panel is the only watcher, so an autoDispose family would drop the write
/// the moment the user switches to Explorer, re-enabling every control and
/// throwing away the snapshot the runtime is about to answer with.

final class SourceControlActionsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SourceControlActionsController,
          MobileGitWriteAction?,
          MobileGitWriteAction?,
          MobileGitWriteAction?,
          (String, String)
        > {
  SourceControlActionsControllerFamily._()
    : super(
        retry: null,
        name: r'sourceControlActionsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Runs source control writes for one workspace and holds the one in flight,
  /// so every control can disable itself while the runtime works.
  ///
  /// Kept alive because a fetch or a push runs for minutes: the Source Control
  /// panel is the only watcher, so an autoDispose family would drop the write
  /// the moment the user switches to Explorer, re-enabling every control and
  /// throwing away the snapshot the runtime is about to answer with.

  SourceControlActionsControllerProvider call(
    String hostId,
    String workspaceId,
  ) => SourceControlActionsControllerProvider._(
    argument: (hostId, workspaceId),
    from: this,
  );

  @override
  String toString() => r'sourceControlActionsControllerProvider';
}

/// Runs source control writes for one workspace and holds the one in flight,
/// so every control can disable itself while the runtime works.
///
/// Kept alive because a fetch or a push runs for minutes: the Source Control
/// panel is the only watcher, so an autoDispose family would drop the write
/// the moment the user switches to Explorer, re-enabling every control and
/// throwing away the snapshot the runtime is about to answer with.

abstract class _$SourceControlActionsController
    extends $Notifier<MobileGitWriteAction?> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  MobileGitWriteAction? build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MobileGitWriteAction?, MobileGitWriteAction?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MobileGitWriteAction?, MobileGitWriteAction?>,
              MobileGitWriteAction?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
