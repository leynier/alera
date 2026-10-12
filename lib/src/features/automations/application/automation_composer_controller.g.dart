// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_composer_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One composer dialog. Every edit is checked locally at once; once the draft
/// is complete the runtime checks it too (`automation.readiness`), shortly
/// after the user stops editing, so its target, profile and host problems
/// show before saving. Nothing here asks for approval.

@ProviderFor(AutomationComposerController)
final automationComposerControllerProvider =
    AutomationComposerControllerFamily._();

/// One composer dialog. Every edit is checked locally at once; once the draft
/// is complete the runtime checks it too (`automation.readiness`), shortly
/// after the user stops editing, so its target, profile and host problems
/// show before saving. Nothing here asks for approval.
final class AutomationComposerControllerProvider
    extends
        $NotifierProvider<
          AutomationComposerController,
          AutomationComposerState
        > {
  /// One composer dialog. Every edit is checked locally at once; once the draft
  /// is complete the runtime checks it too (`automation.readiness`), shortly
  /// after the user stops editing, so its target, profile and host problems
  /// show before saving. Nothing here asks for approval.
  AutomationComposerControllerProvider._({
    required AutomationComposerControllerFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'automationComposerControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$automationComposerControllerHash();

  @override
  String toString() {
    return r'automationComposerControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AutomationComposerController create() => AutomationComposerController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AutomationComposerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AutomationComposerState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AutomationComposerControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$automationComposerControllerHash() =>
    r'2123c073140f21ad3177603c9193509a8415caca';

/// One composer dialog. Every edit is checked locally at once; once the draft
/// is complete the runtime checks it too (`automation.readiness`), shortly
/// after the user stops editing, so its target, profile and host problems
/// show before saving. Nothing here asks for approval.

final class AutomationComposerControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AutomationComposerController,
          AutomationComposerState,
          AutomationComposerState,
          AutomationComposerState,
          int
        > {
  AutomationComposerControllerFamily._()
    : super(
        retry: null,
        name: r'automationComposerControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One composer dialog. Every edit is checked locally at once; once the draft
  /// is complete the runtime checks it too (`automation.readiness`), shortly
  /// after the user stops editing, so its target, profile and host problems
  /// show before saving. Nothing here asks for approval.

  AutomationComposerControllerProvider call(int session) =>
      AutomationComposerControllerProvider._(argument: session, from: this);

  @override
  String toString() => r'automationComposerControllerProvider';
}

/// One composer dialog. Every edit is checked locally at once; once the draft
/// is complete the runtime checks it too (`automation.readiness`), shortly
/// after the user stops editing, so its target, profile and host problems
/// show before saving. Nothing here asks for approval.

abstract class _$AutomationComposerController
    extends $Notifier<AutomationComposerState> {
  late final _$args = ref.$arg as int;
  int get session => _$args;

  AutomationComposerState build(int session);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AutomationComposerState, AutomationComposerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AutomationComposerState, AutomationComposerState>,
              AutomationComposerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
