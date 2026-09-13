// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_control_view_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SourceControlViewController)
final sourceControlViewControllerProvider =
    SourceControlViewControllerFamily._();

final class SourceControlViewControllerProvider
    extends
        $NotifierProvider<SourceControlViewController, SourceControlViewState> {
  SourceControlViewControllerProvider._({
    required SourceControlViewControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'sourceControlViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sourceControlViewControllerHash();

  @override
  String toString() {
    return r'sourceControlViewControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SourceControlViewController create() => SourceControlViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourceControlViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourceControlViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SourceControlViewControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sourceControlViewControllerHash() =>
    r'977a5d04c1bbd98297e21190bf4828cf922d5346';

final class SourceControlViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SourceControlViewController,
          SourceControlViewState,
          SourceControlViewState,
          SourceControlViewState,
          (String, String)
        > {
  SourceControlViewControllerFamily._()
    : super(
        retry: null,
        name: r'sourceControlViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SourceControlViewControllerProvider call(String hostId, String workspaceId) =>
      SourceControlViewControllerProvider._(
        argument: (hostId, workspaceId),
        from: this,
      );

  @override
  String toString() => r'sourceControlViewControllerProvider';
}

abstract class _$SourceControlViewController
    extends $Notifier<SourceControlViewState> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  SourceControlViewState build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<SourceControlViewState, SourceControlViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SourceControlViewState, SourceControlViewState>,
              SourceControlViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
