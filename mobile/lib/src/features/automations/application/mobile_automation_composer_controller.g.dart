// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_automation_composer_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One composer screen, for creating and editing. Every edit is checked
/// locally at once; once the draft is complete the runtime checks it too
/// (`automation.readiness`) shortly after the user stops editing, so target,
/// profile and host problems show before saving. Nothing asks for approval.

@ProviderFor(MobileAutomationComposerController)
final mobileAutomationComposerControllerProvider =
    MobileAutomationComposerControllerFamily._();

/// One composer screen, for creating and editing. Every edit is checked
/// locally at once; once the draft is complete the runtime checks it too
/// (`automation.readiness`) shortly after the user stops editing, so target,
/// profile and host problems show before saving. Nothing asks for approval.
final class MobileAutomationComposerControllerProvider
    extends
        $NotifierProvider<
          MobileAutomationComposerController,
          MobileAutomationComposerState
        > {
  /// One composer screen, for creating and editing. Every edit is checked
  /// locally at once; once the draft is complete the runtime checks it too
  /// (`automation.readiness`) shortly after the user stops editing, so target,
  /// profile and host problems show before saving. Nothing asks for approval.
  MobileAutomationComposerControllerProvider._({
    required MobileAutomationComposerControllerFamily super.from,
    required (String, int) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationComposerControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$mobileAutomationComposerControllerHash();

  @override
  String toString() {
    return r'mobileAutomationComposerControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileAutomationComposerController create() =>
      MobileAutomationComposerController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileAutomationComposerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileAutomationComposerState>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationComposerControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationComposerControllerHash() =>
    r'd2dfd6848bcde052f0129605d450a13bec8a397a';

/// One composer screen, for creating and editing. Every edit is checked
/// locally at once; once the draft is complete the runtime checks it too
/// (`automation.readiness`) shortly after the user stops editing, so target,
/// profile and host problems show before saving. Nothing asks for approval.

final class MobileAutomationComposerControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAutomationComposerController,
          MobileAutomationComposerState,
          MobileAutomationComposerState,
          MobileAutomationComposerState,
          (String, int)
        > {
  MobileAutomationComposerControllerFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationComposerControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One composer screen, for creating and editing. Every edit is checked
  /// locally at once; once the draft is complete the runtime checks it too
  /// (`automation.readiness`) shortly after the user stops editing, so target,
  /// profile and host problems show before saving. Nothing asks for approval.

  MobileAutomationComposerControllerProvider call(String hostId, int session) =>
      MobileAutomationComposerControllerProvider._(
        argument: (hostId, session),
        from: this,
      );

  @override
  String toString() => r'mobileAutomationComposerControllerProvider';
}

/// One composer screen, for creating and editing. Every edit is checked
/// locally at once; once the draft is complete the runtime checks it too
/// (`automation.readiness`) shortly after the user stops editing, so target,
/// profile and host problems show before saving. Nothing asks for approval.

abstract class _$MobileAutomationComposerController
    extends $Notifier<MobileAutomationComposerState> {
  late final _$args = ref.$arg as (String, int);
  String get hostId => _$args.$1;
  int get session => _$args.$2;

  MobileAutomationComposerState build(String hostId, int session);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              MobileAutomationComposerState,
              MobileAutomationComposerState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                MobileAutomationComposerState,
                MobileAutomationComposerState
              >,
              MobileAutomationComposerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
