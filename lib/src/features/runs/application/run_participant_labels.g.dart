// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_participant_labels.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Readable names for the terminal handles in a run's timeline: the tab
/// title and agent the sidebar knows. Unknown handles keep their raw id.

@ProviderFor(runParticipantLabels)
final runParticipantLabelsProvider = RunParticipantLabelsProvider._();

/// Readable names for the terminal handles in a run's timeline: the tab
/// title and agent the sidebar knows. Unknown handles keep their raw id.

final class RunParticipantLabelsProvider
    extends
        $FunctionalProvider<
          Map<String, String>,
          Map<String, String>,
          Map<String, String>
        >
    with $Provider<Map<String, String>> {
  /// Readable names for the terminal handles in a run's timeline: the tab
  /// title and agent the sidebar knows. Unknown handles keep their raw id.
  RunParticipantLabelsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runParticipantLabelsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runParticipantLabelsHash();

  @$internal
  @override
  $ProviderElement<Map<String, String>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, String> create(Ref ref) {
    return runParticipantLabels(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, String>>(value),
    );
  }
}

String _$runParticipantLabelsHash() =>
    r'65127ea048601393c7957d45b1de249dbb2b7375';
