// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Which part of Activity is open, kept per host while the app runs.

@ProviderFor(MobileActivitySectionController)
final mobileActivitySectionControllerProvider =
    MobileActivitySectionControllerFamily._();

/// Which part of Activity is open, kept per host while the app runs.
final class MobileActivitySectionControllerProvider
    extends
        $NotifierProvider<MobileActivitySectionController, ActivitySection> {
  /// Which part of Activity is open, kept per host while the app runs.
  MobileActivitySectionControllerProvider._({
    required MobileActivitySectionControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileActivitySectionControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileActivitySectionControllerHash();

  @override
  String toString() {
    return r'mobileActivitySectionControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileActivitySectionController create() => MobileActivitySectionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActivitySection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActivitySection>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileActivitySectionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileActivitySectionControllerHash() =>
    r'8c599c3e2245c639f50cc57c1af6659c5498435c';

/// Which part of Activity is open, kept per host while the app runs.

final class MobileActivitySectionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileActivitySectionController,
          ActivitySection,
          ActivitySection,
          ActivitySection,
          String
        > {
  MobileActivitySectionControllerFamily._()
    : super(
        retry: null,
        name: r'mobileActivitySectionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Which part of Activity is open, kept per host while the app runs.

  MobileActivitySectionControllerProvider call(String hostId) =>
      MobileActivitySectionControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileActivitySectionControllerProvider';
}

/// Which part of Activity is open, kept per host while the app runs.

abstract class _$MobileActivitySectionController
    extends $Notifier<ActivitySection> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  ActivitySection build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ActivitySection, ActivitySection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ActivitySection, ActivitySection>,
              ActivitySection,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Replies nobody has read yet, across every inbox of the host.

@ProviderFor(mobileQuestionUnreadCount)
final mobileQuestionUnreadCountProvider = MobileQuestionUnreadCountFamily._();

/// Replies nobody has read yet, across every inbox of the host.

final class MobileQuestionUnreadCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Replies nobody has read yet, across every inbox of the host.
  MobileQuestionUnreadCountProvider._({
    required MobileQuestionUnreadCountFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileQuestionUnreadCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileQuestionUnreadCountHash();

  @override
  String toString() {
    return r'mobileQuestionUnreadCountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    final argument = this.argument as String;
    return mobileQuestionUnreadCount(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileQuestionUnreadCountProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileQuestionUnreadCountHash() =>
    r'5a095baaa3e3fabca6cd9e1307b26681c46eebaf';

/// Replies nobody has read yet, across every inbox of the host.

final class MobileQuestionUnreadCountFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<int>, String> {
  MobileQuestionUnreadCountFamily._()
    : super(
        retry: null,
        name: r'mobileQuestionUnreadCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Replies nobody has read yet, across every inbox of the host.

  MobileQuestionUnreadCountProvider call(String hostId) =>
      MobileQuestionUnreadCountProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileQuestionUnreadCountProvider';
}

/// Automations that are blocked or report a problem.

@ProviderFor(mobileAutomationAttentionCount)
final mobileAutomationAttentionCountProvider =
    MobileAutomationAttentionCountFamily._();

/// Automations that are blocked or report a problem.

final class MobileAutomationAttentionCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Automations that are blocked or report a problem.
  MobileAutomationAttentionCountProvider._({
    required MobileAutomationAttentionCountFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationAttentionCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationAttentionCountHash();

  @override
  String toString() {
    return r'mobileAutomationAttentionCountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    final argument = this.argument as String;
    return mobileAutomationAttentionCount(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationAttentionCountProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationAttentionCountHash() =>
    r'5a952d67623bbc07b3682cd5d208026697e7f3ff';

/// Automations that are blocked or report a problem.

final class MobileAutomationAttentionCountFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<int>, String> {
  MobileAutomationAttentionCountFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationAttentionCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Automations that are blocked or report a problem.

  MobileAutomationAttentionCountProvider call(String hostId) =>
      MobileAutomationAttentionCountProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationAttentionCountProvider';
}
