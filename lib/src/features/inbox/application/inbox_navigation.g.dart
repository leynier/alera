// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_navigation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(InboxNavigation)
final inboxNavigationProvider = InboxNavigationProvider._();

final class InboxNavigationProvider
    extends $NotifierProvider<InboxNavigation, InboxLocation> {
  InboxNavigationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inboxNavigationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inboxNavigationHash();

  @$internal
  @override
  InboxNavigation create() => InboxNavigation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(InboxLocation value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<InboxLocation>(value),
    );
  }
}

String _$inboxNavigationHash() => r'3a80dd5cb66c2b547301abf4e3dd18b1367a1822';

abstract class _$InboxNavigation extends $Notifier<InboxLocation> {
  InboxLocation build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<InboxLocation, InboxLocation>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<InboxLocation, InboxLocation>,
              InboxLocation,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
