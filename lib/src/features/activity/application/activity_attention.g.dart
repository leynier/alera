// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_attention.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(activityAttention)
final activityAttentionProvider = ActivityAttentionProvider._();

final class ActivityAttentionProvider
    extends
        $FunctionalProvider<
          ActivityAttention,
          ActivityAttention,
          ActivityAttention
        >
    with $Provider<ActivityAttention> {
  ActivityAttentionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activityAttentionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activityAttentionHash();

  @$internal
  @override
  $ProviderElement<ActivityAttention> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ActivityAttention create(Ref ref) {
    return activityAttention(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActivityAttention value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActivityAttention>(value),
    );
  }
}

String _$activityAttentionHash() => r'70025c63e7ad4e8b6fd31362ab2934c60c78b569';
