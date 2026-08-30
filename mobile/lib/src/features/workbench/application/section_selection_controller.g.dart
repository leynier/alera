// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'section_selection_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SectionSelectionController)
final sectionSelectionControllerProvider = SectionSelectionControllerFamily._();

final class SectionSelectionControllerProvider
    extends
        $AsyncNotifierProvider<
          SectionSelectionController,
          SectionSelectionState
        > {
  SectionSelectionControllerProvider._({
    required SectionSelectionControllerFamily super.from,
    required (String, String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'sectionSelectionControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sectionSelectionControllerHash();

  @override
  String toString() {
    return r'sectionSelectionControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SectionSelectionController create() => SectionSelectionController();

  @override
  bool operator ==(Object other) {
    return other is SectionSelectionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sectionSelectionControllerHash() =>
    r'9316984d92ed4bad991cfeb4446264b7d50973ea';

final class SectionSelectionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SectionSelectionController,
          AsyncValue<SectionSelectionState>,
          SectionSelectionState,
          FutureOr<SectionSelectionState>,
          (String, String, String?)
        > {
  SectionSelectionControllerFamily._()
    : super(
        retry: null,
        name: r'sectionSelectionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SectionSelectionControllerProvider call(
    String hostId,
    String workspaceId,
    String? initialSectionId,
  ) => SectionSelectionControllerProvider._(
    argument: (hostId, workspaceId, initialSectionId),
    from: this,
  );

  @override
  String toString() => r'sectionSelectionControllerProvider';
}

abstract class _$SectionSelectionController
    extends $AsyncNotifier<SectionSelectionState> {
  late final _$args = ref.$arg as (String, String, String?);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;
  String? get initialSectionId => _$args.$3;

  FutureOr<SectionSelectionState> build(
    String hostId,
    String workspaceId,
    String? initialSectionId,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<SectionSelectionState>, SectionSelectionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SectionSelectionState>,
                SectionSelectionState
              >,
              AsyncValue<SectionSelectionState>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3),
    );
  }
}
