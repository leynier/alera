// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diagnostics_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(diagnosticsService)
final diagnosticsServiceProvider = DiagnosticsServiceProvider._();

final class DiagnosticsServiceProvider
    extends
        $FunctionalProvider<
          DiagnosticsService,
          DiagnosticsService,
          DiagnosticsService
        >
    with $Provider<DiagnosticsService> {
  DiagnosticsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diagnosticsServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diagnosticsServiceHash();

  @$internal
  @override
  $ProviderElement<DiagnosticsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DiagnosticsService create(Ref ref) {
    return diagnosticsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DiagnosticsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DiagnosticsService>(value),
    );
  }
}

String _$diagnosticsServiceHash() =>
    r'de4b5add21e6be6ab7f729c6c486250204018075';

/// Applies the stored diagnostics settings to the live logger and to crash
/// reporting.
///
/// Settings load after startup, so the values chosen at boot are defaults; this
/// is what makes the user's actual choice take effect, and it re-runs on every
/// change so turning reporting off stops it immediately.

@ProviderFor(diagnosticsSettingsApplier)
final diagnosticsSettingsApplierProvider =
    DiagnosticsSettingsApplierProvider._();

/// Applies the stored diagnostics settings to the live logger and to crash
/// reporting.
///
/// Settings load after startup, so the values chosen at boot are defaults; this
/// is what makes the user's actual choice take effect, and it re-runs on every
/// change so turning reporting off stops it immediately.

final class DiagnosticsSettingsApplierProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Applies the stored diagnostics settings to the live logger and to crash
  /// reporting.
  ///
  /// Settings load after startup, so the values chosen at boot are defaults; this
  /// is what makes the user's actual choice take effect, and it re-runs on every
  /// change so turning reporting off stops it immediately.
  DiagnosticsSettingsApplierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diagnosticsSettingsApplierProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diagnosticsSettingsApplierHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return diagnosticsSettingsApplier(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$diagnosticsSettingsApplierHash() =>
    r'f1927dde79046309ef2c9f0fd7aeea494e3ffb87';

/// Runtime facts for the bundle, read from a live host.
///
/// A host that is down, or one older than `hostDiagnosticsLogsV1`, yields an
/// info with no log directory rather than an error: a bundle without the
/// runtime section is still the most useful thing available at that point.

@ProviderFor(runtimeDiagnosticsInfo)
final runtimeDiagnosticsInfoProvider = RuntimeDiagnosticsInfoProvider._();

/// Runtime facts for the bundle, read from a live host.
///
/// A host that is down, or one older than `hostDiagnosticsLogsV1`, yields an
/// info with no log directory rather than an error: a bundle without the
/// runtime section is still the most useful thing available at that point.

final class RuntimeDiagnosticsInfoProvider
    extends
        $FunctionalProvider<
          AsyncValue<RuntimeDiagnosticsInfo>,
          RuntimeDiagnosticsInfo,
          FutureOr<RuntimeDiagnosticsInfo>
        >
    with
        $FutureModifier<RuntimeDiagnosticsInfo>,
        $FutureProvider<RuntimeDiagnosticsInfo> {
  /// Runtime facts for the bundle, read from a live host.
  ///
  /// A host that is down, or one older than `hostDiagnosticsLogsV1`, yields an
  /// info with no log directory rather than an error: a bundle without the
  /// runtime section is still the most useful thing available at that point.
  RuntimeDiagnosticsInfoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeDiagnosticsInfoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeDiagnosticsInfoHash();

  @$internal
  @override
  $FutureProviderElement<RuntimeDiagnosticsInfo> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RuntimeDiagnosticsInfo> create(Ref ref) {
    return runtimeDiagnosticsInfo(ref);
  }
}

String _$runtimeDiagnosticsInfoHash() =>
    r'3f9f3f186030312d6f6d9cbbecc6679d3f9937ad';
