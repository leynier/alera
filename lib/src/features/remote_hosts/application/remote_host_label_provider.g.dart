// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_host_label_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The name the UI shows for [hostId]: the host's alias, "This Device" for
/// the local host, or the raw id once the host is no longer registered.

@ProviderFor(remoteHostLabel)
final remoteHostLabelProvider = RemoteHostLabelFamily._();

/// The name the UI shows for [hostId]: the host's alias, "This Device" for
/// the local host, or the raw id once the host is no longer registered.

final class RemoteHostLabelProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The name the UI shows for [hostId]: the host's alias, "This Device" for
  /// the local host, or the raw id once the host is no longer registered.
  RemoteHostLabelProvider._({
    required RemoteHostLabelFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'remoteHostLabelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$remoteHostLabelHash();

  @override
  String toString() {
    return r'remoteHostLabelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    final argument = this.argument as String?;
    return remoteHostLabel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RemoteHostLabelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$remoteHostLabelHash() => r'3584d39266a7ab98e651c08bd296ca332aaaec55';

/// The name the UI shows for [hostId]: the host's alias, "This Device" for
/// the local host, or the raw id once the host is no longer registered.

final class RemoteHostLabelFamily extends $Family
    with $FunctionalFamilyOverride<String, String?> {
  RemoteHostLabelFamily._()
    : super(
        retry: null,
        name: r'remoteHostLabelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The name the UI shows for [hostId]: the host's alias, "This Device" for
  /// the local host, or the raw id once the host is no longer registered.

  RemoteHostLabelProvider call(String? hostId) =>
      RemoteHostLabelProvider._(argument: hostId, from: this);

  @override
  String toString() => r'remoteHostLabelProvider';
}
