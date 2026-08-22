// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tabs_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tabs of one workspace. The mobile app shows one tab at a time; splits stay
/// a desktop concept.

@ProviderFor(TabsController)
final tabsControllerProvider = TabsControllerFamily._();

/// Tabs of one workspace. The mobile app shows one tab at a time; splits stay
/// a desktop concept.
final class TabsControllerProvider
    extends $AsyncNotifierProvider<TabsController, List<WorkspaceTabSummary>> {
  /// Tabs of one workspace. The mobile app shows one tab at a time; splits stay
  /// a desktop concept.
  TabsControllerProvider._({
    required TabsControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'tabsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tabsControllerHash();

  @override
  String toString() {
    return r'tabsControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  TabsController create() => TabsController();

  @override
  bool operator ==(Object other) {
    return other is TabsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tabsControllerHash() => r'083b089a20b20adf7217931dc74d68f37022022b';

/// Tabs of one workspace. The mobile app shows one tab at a time; splits stay
/// a desktop concept.

final class TabsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          TabsController,
          AsyncValue<List<WorkspaceTabSummary>>,
          List<WorkspaceTabSummary>,
          FutureOr<List<WorkspaceTabSummary>>,
          (String, String)
        > {
  TabsControllerFamily._()
    : super(
        retry: null,
        name: r'tabsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Tabs of one workspace. The mobile app shows one tab at a time; splits stay
  /// a desktop concept.

  TabsControllerProvider call(String hostId, String workspaceId) =>
      TabsControllerProvider._(argument: (hostId, workspaceId), from: this);

  @override
  String toString() => r'tabsControllerProvider';
}

/// Tabs of one workspace. The mobile app shows one tab at a time; splits stay
/// a desktop concept.

abstract class _$TabsController
    extends $AsyncNotifier<List<WorkspaceTabSummary>> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  FutureOr<List<WorkspaceTabSummary>> build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<WorkspaceTabSummary>>,
              List<WorkspaceTabSummary>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<WorkspaceTabSummary>>,
                List<WorkspaceTabSummary>
              >,
              AsyncValue<List<WorkspaceTabSummary>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
