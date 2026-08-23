// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_tools_controllers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SkillRunnerSelection)
final skillRunnerSelectionProvider = SkillRunnerSelectionFamily._();

final class SkillRunnerSelectionProvider
    extends $NotifierProvider<SkillRunnerSelection, String> {
  SkillRunnerSelectionProvider._({
    required SkillRunnerSelectionFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'skillRunnerSelectionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$skillRunnerSelectionHash();

  @override
  String toString() {
    return r'skillRunnerSelectionProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SkillRunnerSelection create() => SkillRunnerSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SkillRunnerSelectionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$skillRunnerSelectionHash() =>
    r'44a33ffedfcfd65e458e2f9c54ee38a649c8a3d6';

final class SkillRunnerSelectionFamily extends $Family
    with
        $ClassFamilyOverride<
          SkillRunnerSelection,
          String,
          String,
          String,
          (String, String)
        > {
  SkillRunnerSelectionFamily._()
    : super(
        retry: null,
        name: r'skillRunnerSelectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SkillRunnerSelectionProvider call(String hostId, String skill) =>
      SkillRunnerSelectionProvider._(argument: (hostId, skill), from: this);

  @override
  String toString() => r'skillRunnerSelectionProvider';
}

abstract class _$SkillRunnerSelection extends $Notifier<String> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get skill => _$args.$2;

  String build(String hostId, String skill);
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

@ProviderFor(CliRegistrationController)
final cliRegistrationControllerProvider = CliRegistrationControllerFamily._();

final class CliRegistrationControllerProvider
    extends
        $AsyncNotifierProvider<
          CliRegistrationController,
          CliRegistrationStatus
        > {
  CliRegistrationControllerProvider._({
    required CliRegistrationControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'cliRegistrationControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cliRegistrationControllerHash();

  @override
  String toString() {
    return r'cliRegistrationControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CliRegistrationController create() => CliRegistrationController();

  @override
  bool operator ==(Object other) {
    return other is CliRegistrationControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cliRegistrationControllerHash() =>
    r'11f22898588558c326c21dad2618b73fdaaf9504';

final class CliRegistrationControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          CliRegistrationController,
          AsyncValue<CliRegistrationStatus>,
          CliRegistrationStatus,
          FutureOr<CliRegistrationStatus>,
          String
        > {
  CliRegistrationControllerFamily._()
    : super(
        retry: null,
        name: r'cliRegistrationControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CliRegistrationControllerProvider call(String hostId) =>
      CliRegistrationControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'cliRegistrationControllerProvider';
}

abstract class _$CliRegistrationController
    extends $AsyncNotifier<CliRegistrationStatus> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<CliRegistrationStatus> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<CliRegistrationStatus>, CliRegistrationStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<CliRegistrationStatus>,
                CliRegistrationStatus
              >,
              AsyncValue<CliRegistrationStatus>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(SkillInstallController)
final skillInstallControllerProvider = SkillInstallControllerFamily._();

final class SkillInstallControllerProvider
    extends $NotifierProvider<SkillInstallController, SkillInstallState> {
  SkillInstallControllerProvider._({
    required SkillInstallControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'skillInstallControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$skillInstallControllerHash();

  @override
  String toString() {
    return r'skillInstallControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SkillInstallController create() => SkillInstallController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SkillInstallState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SkillInstallState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SkillInstallControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$skillInstallControllerHash() =>
    r'b135f90d2ddbc8ed8b0eb0235374523acb9e0480';

final class SkillInstallControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SkillInstallController,
          SkillInstallState,
          SkillInstallState,
          SkillInstallState,
          (String, String)
        > {
  SkillInstallControllerFamily._()
    : super(
        retry: null,
        name: r'skillInstallControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SkillInstallControllerProvider call(String hostId, String skill) =>
      SkillInstallControllerProvider._(argument: (hostId, skill), from: this);

  @override
  String toString() => r'skillInstallControllerProvider';
}

abstract class _$SkillInstallController extends $Notifier<SkillInstallState> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get skill => _$args.$2;

  SkillInstallState build(String hostId, String skill);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SkillInstallState, SkillInstallState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SkillInstallState, SkillInstallState>,
              SkillInstallState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
