// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'terminal_input_mode_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Per-tab input mode. Compose is the default; switching to direct is a
/// per-terminal opt-in that sticks for the app session but is not persisted
/// across launches (mirrors Orca's scoping with the default inverted).

@ProviderFor(TerminalInputModeController)
final terminalInputModeControllerProvider =
    TerminalInputModeControllerFamily._();

/// Per-tab input mode. Compose is the default; switching to direct is a
/// per-terminal opt-in that sticks for the app session but is not persisted
/// across launches (mirrors Orca's scoping with the default inverted).
final class TerminalInputModeControllerProvider
    extends $NotifierProvider<TerminalInputModeController, TerminalInputMode> {
  /// Per-tab input mode. Compose is the default; switching to direct is a
  /// per-terminal opt-in that sticks for the app session but is not persisted
  /// across launches (mirrors Orca's scoping with the default inverted).
  TerminalInputModeControllerProvider._({
    required TerminalInputModeControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'terminalInputModeControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$terminalInputModeControllerHash();

  @override
  String toString() {
    return r'terminalInputModeControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TerminalInputModeController create() => TerminalInputModeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TerminalInputMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TerminalInputMode>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalInputModeControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$terminalInputModeControllerHash() =>
    r'3b8372611052cb05dda0067ed6dcb68d5ad153d9';

/// Per-tab input mode. Compose is the default; switching to direct is a
/// per-terminal opt-in that sticks for the app session but is not persisted
/// across launches (mirrors Orca's scoping with the default inverted).

final class TerminalInputModeControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          TerminalInputModeController,
          TerminalInputMode,
          TerminalInputMode,
          TerminalInputMode,
          String
        > {
  TerminalInputModeControllerFamily._()
    : super(
        retry: null,
        name: r'terminalInputModeControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Per-tab input mode. Compose is the default; switching to direct is a
  /// per-terminal opt-in that sticks for the app session but is not persisted
  /// across launches (mirrors Orca's scoping with the default inverted).

  TerminalInputModeControllerProvider call(String tabId) =>
      TerminalInputModeControllerProvider._(argument: tabId, from: this);

  @override
  String toString() => r'terminalInputModeControllerProvider';
}

/// Per-tab input mode. Compose is the default; switching to direct is a
/// per-terminal opt-in that sticks for the app session but is not persisted
/// across launches (mirrors Orca's scoping with the default inverted).

abstract class _$TerminalInputModeController
    extends $Notifier<TerminalInputMode> {
  late final _$args = ref.$arg as String;
  String get tabId => _$args;

  TerminalInputMode build(String tabId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TerminalInputMode, TerminalInputMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TerminalInputMode, TerminalInputMode>,
              TerminalInputMode,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
