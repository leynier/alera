// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'terminal_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The terminal surface of the host connection. Tests override this with a
/// fake so tab and session controllers can run without a live gateway.

@ProviderFor(terminalClient)
final terminalClientProvider = TerminalClientFamily._();

/// The terminal surface of the host connection. Tests override this with a
/// fake so tab and session controllers can run without a live gateway.

final class TerminalClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileTerminalClient>,
          MobileTerminalClient,
          FutureOr<MobileTerminalClient>
        >
    with
        $FutureModifier<MobileTerminalClient>,
        $FutureProvider<MobileTerminalClient> {
  /// The terminal surface of the host connection. Tests override this with a
  /// fake so tab and session controllers can run without a live gateway.
  TerminalClientProvider._({
    required TerminalClientFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'terminalClientProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$terminalClientHash();

  @override
  String toString() {
    return r'terminalClientProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileTerminalClient> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileTerminalClient> create(Ref ref) {
    final argument = this.argument as String;
    return terminalClient(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalClientProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$terminalClientHash() => r'65a9f80d83eddbc9c662f98d16b9d5c76668e095';

/// The terminal surface of the host connection. Tests override this with a
/// fake so tab and session controllers can run without a live gateway.

final class TerminalClientFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MobileTerminalClient>, String> {
  TerminalClientFamily._()
    : super(
        retry: null,
        name: r'terminalClientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The terminal surface of the host connection. Tests override this with a
  /// fake so tab and session controllers can run without a live gateway.

  TerminalClientProvider call(String hostId) =>
      TerminalClientProvider._(argument: hostId, from: this);

  @override
  String toString() => r'terminalClientProvider';
}
