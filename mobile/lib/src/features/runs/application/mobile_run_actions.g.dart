// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_run_actions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Mutations of one run. Each user action gets its own `requestId`, so the
/// runtime replays a receipt instead of acting twice when a reply is lost,
/// and carries what the user saw (`expectedSequence`,
/// `expectedEvidenceDigest`), so a decision on stale state is refused.

@ProviderFor(MobileRunActions)
final mobileRunActionsProvider = MobileRunActionsFamily._();

/// Mutations of one run. Each user action gets its own `requestId`, so the
/// runtime replays a receipt instead of acting twice when a reply is lost,
/// and carries what the user saw (`expectedSequence`,
/// `expectedEvidenceDigest`), so a decision on stale state is refused.
final class MobileRunActionsProvider
    extends $NotifierProvider<MobileRunActions, MobileRunActionState> {
  /// Mutations of one run. Each user action gets its own `requestId`, so the
  /// runtime replays a receipt instead of acting twice when a reply is lost,
  /// and carries what the user saw (`expectedSequence`,
  /// `expectedEvidenceDigest`), so a decision on stale state is refused.
  MobileRunActionsProvider._({
    required MobileRunActionsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunActionsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunActionsHash();

  @override
  String toString() {
    return r'mobileRunActionsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileRunActions create() => MobileRunActions();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileRunActionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileRunActionState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileRunActionsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunActionsHash() => r'617f1ea7ca0726bef3a17fee397bb8d528c46058';

/// Mutations of one run. Each user action gets its own `requestId`, so the
/// runtime replays a receipt instead of acting twice when a reply is lost,
/// and carries what the user saw (`expectedSequence`,
/// `expectedEvidenceDigest`), so a decision on stale state is refused.

final class MobileRunActionsFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileRunActions,
          MobileRunActionState,
          MobileRunActionState,
          MobileRunActionState,
          (String, String)
        > {
  MobileRunActionsFamily._()
    : super(
        retry: null,
        name: r'mobileRunActionsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Mutations of one run. Each user action gets its own `requestId`, so the
  /// runtime replays a receipt instead of acting twice when a reply is lost,
  /// and carries what the user saw (`expectedSequence`,
  /// `expectedEvidenceDigest`), so a decision on stale state is refused.

  MobileRunActionsProvider call(String hostId, String runId) =>
      MobileRunActionsProvider._(argument: (hostId, runId), from: this);

  @override
  String toString() => r'mobileRunActionsProvider';
}

/// Mutations of one run. Each user action gets its own `requestId`, so the
/// runtime replays a receipt instead of acting twice when a reply is lost,
/// and carries what the user saw (`expectedSequence`,
/// `expectedEvidenceDigest`), so a decision on stale state is refused.

abstract class _$MobileRunActions extends $Notifier<MobileRunActionState> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get runId => _$args.$2;

  MobileRunActionState build(String hostId, String runId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MobileRunActionState, MobileRunActionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MobileRunActionState, MobileRunActionState>,
              MobileRunActionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
