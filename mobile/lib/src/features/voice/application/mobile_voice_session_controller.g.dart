// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_voice_session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MobileVoiceSessionController)
final mobileVoiceSessionControllerProvider =
    MobileVoiceSessionControllerFamily._();

final class MobileVoiceSessionControllerProvider
    extends
        $NotifierProvider<
          MobileVoiceSessionController,
          MobileVoiceSessionState
        > {
  MobileVoiceSessionControllerProvider._({
    required MobileVoiceSessionControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileVoiceSessionControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileVoiceSessionControllerHash();

  @override
  String toString() {
    return r'mobileVoiceSessionControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileVoiceSessionController create() => MobileVoiceSessionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileVoiceSessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileVoiceSessionState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileVoiceSessionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileVoiceSessionControllerHash() =>
    r'5b2842911f90ae2323667fc931130f3bd6b5ebef';

final class MobileVoiceSessionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileVoiceSessionController,
          MobileVoiceSessionState,
          MobileVoiceSessionState,
          MobileVoiceSessionState,
          String
        > {
  MobileVoiceSessionControllerFamily._()
    : super(
        retry: null,
        name: r'mobileVoiceSessionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileVoiceSessionControllerProvider call(String hostId) =>
      MobileVoiceSessionControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileVoiceSessionControllerProvider';
}

abstract class _$MobileVoiceSessionController
    extends $Notifier<MobileVoiceSessionState> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  MobileVoiceSessionState build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<MobileVoiceSessionState, MobileVoiceSessionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MobileVoiceSessionState, MobileVoiceSessionState>,
              MobileVoiceSessionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
