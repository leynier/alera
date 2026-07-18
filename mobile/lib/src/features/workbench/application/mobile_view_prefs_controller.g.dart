// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_view_prefs_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MobileViewPrefsController)
final mobileViewPrefsControllerProvider = MobileViewPrefsControllerFamily._();

final class MobileViewPrefsControllerProvider
    extends $AsyncNotifierProvider<MobileViewPrefsController, MobileViewPrefs> {
  MobileViewPrefsControllerProvider._({
    required MobileViewPrefsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileViewPrefsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileViewPrefsControllerHash();

  @override
  String toString() {
    return r'mobileViewPrefsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileViewPrefsController create() => MobileViewPrefsController();

  @override
  bool operator ==(Object other) {
    return other is MobileViewPrefsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileViewPrefsControllerHash() =>
    r'eac39d3bba03dc6e742bff7a38da5d857498bfd6';

final class MobileViewPrefsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileViewPrefsController,
          AsyncValue<MobileViewPrefs>,
          MobileViewPrefs,
          FutureOr<MobileViewPrefs>,
          String
        > {
  MobileViewPrefsControllerFamily._()
    : super(
        retry: null,
        name: r'mobileViewPrefsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileViewPrefsControllerProvider call(String hostId) =>
      MobileViewPrefsControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileViewPrefsControllerProvider';
}

abstract class _$MobileViewPrefsController
    extends $AsyncNotifier<MobileViewPrefs> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<MobileViewPrefs> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<MobileViewPrefs>, MobileViewPrefs>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<MobileViewPrefs>, MobileViewPrefs>,
              AsyncValue<MobileViewPrefs>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
