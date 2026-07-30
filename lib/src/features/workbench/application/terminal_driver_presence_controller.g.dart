// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'terminal_driver_presence_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Mirror of the runtime's terminal driver map (session id -> driver), fed by
/// `terminalDriverChanged` events and bootstrapped from `terminal.driver.list`
/// so overlay state survives app restarts while a phone keeps driving.

@ProviderFor(TerminalDriverPresenceController)
final terminalDriverPresenceControllerProvider =
    TerminalDriverPresenceControllerProvider._();

/// Mirror of the runtime's terminal driver map (session id -> driver), fed by
/// `terminalDriverChanged` events and bootstrapped from `terminal.driver.list`
/// so overlay state survives app restarts while a phone keeps driving.
final class TerminalDriverPresenceControllerProvider
    extends
        $NotifierProvider<
          TerminalDriverPresenceController,
          Map<String, TerminalSessionDriver>
        > {
  /// Mirror of the runtime's terminal driver map (session id -> driver), fed by
  /// `terminalDriverChanged` events and bootstrapped from `terminal.driver.list`
  /// so overlay state survives app restarts while a phone keeps driving.
  TerminalDriverPresenceControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'terminalDriverPresenceControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$terminalDriverPresenceControllerHash();

  @$internal
  @override
  TerminalDriverPresenceController create() =>
      TerminalDriverPresenceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, TerminalSessionDriver> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, TerminalSessionDriver>>(
        value,
      ),
    );
  }
}

String _$terminalDriverPresenceControllerHash() =>
    r'fdfb205d9acf6233eb6af318b07f1b0072f55d50';

/// Mirror of the runtime's terminal driver map (session id -> driver), fed by
/// `terminalDriverChanged` events and bootstrapped from `terminal.driver.list`
/// so overlay state survives app restarts while a phone keeps driving.

abstract class _$TerminalDriverPresenceController
    extends $Notifier<Map<String, TerminalSessionDriver>> {
  Map<String, TerminalSessionDriver> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, TerminalSessionDriver>,
              Map<String, TerminalSessionDriver>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, TerminalSessionDriver>,
                Map<String, TerminalSessionDriver>
              >,
              Map<String, TerminalSessionDriver>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
