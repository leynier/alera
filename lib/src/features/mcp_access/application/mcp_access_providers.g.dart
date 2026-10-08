// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_access_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mcpAccessRepository)
final mcpAccessRepositoryProvider = McpAccessRepositoryProvider._();

final class McpAccessRepositoryProvider
    extends
        $FunctionalProvider<
          McpAccessRepository,
          McpAccessRepository,
          McpAccessRepository
        >
    with $Provider<McpAccessRepository> {
  McpAccessRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpAccessRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpAccessRepositoryHash();

  @$internal
  @override
  $ProviderElement<McpAccessRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  McpAccessRepository create(Ref ref) {
    return mcpAccessRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(McpAccessRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<McpAccessRepository>(value),
    );
  }
}

String _$mcpAccessRepositoryHash() =>
    r'ddf0fbec8727cad866bb318cfba87d33ffa61233';

/// Settings for the open MCP Access pane. Auto-disposed so reopening the pane
/// reads fresh values and the event subscription ends when it closes.

@ProviderFor(McpAccessSettingsController)
final mcpAccessSettingsControllerProvider =
    McpAccessSettingsControllerProvider._();

/// Settings for the open MCP Access pane. Auto-disposed so reopening the pane
/// reads fresh values and the event subscription ends when it closes.
final class McpAccessSettingsControllerProvider
    extends
        $StreamNotifierProvider<
          McpAccessSettingsController,
          McpAccessSettings?
        > {
  /// Settings for the open MCP Access pane. Auto-disposed so reopening the pane
  /// reads fresh values and the event subscription ends when it closes.
  McpAccessSettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noMcpRetry,
        name: r'mcpAccessSettingsControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpAccessSettingsControllerHash();

  @$internal
  @override
  McpAccessSettingsController create() => McpAccessSettingsController();
}

String _$mcpAccessSettingsControllerHash() =>
    r'347ae64d663f22d22a0adf4307a2b5b9b0bb39fd';

/// Settings for the open MCP Access pane. Auto-disposed so reopening the pane
/// reads fresh values and the event subscription ends when it closes.

abstract class _$McpAccessSettingsController
    extends $StreamNotifier<McpAccessSettings?> {
  Stream<McpAccessSettings?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<McpAccessSettings?>, McpAccessSettings?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<McpAccessSettings?>, McpAccessSettings?>,
              AsyncValue<McpAccessSettings?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Grants for the open pane, read again each time the pane is shown.

@ProviderFor(mcpGrants)
final mcpGrantsProvider = McpGrantsProvider._();

/// Grants for the open pane, read again each time the pane is shown.

final class McpGrantsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<McpGrant>>,
          List<McpGrant>,
          FutureOr<List<McpGrant>>
        >
    with $FutureModifier<List<McpGrant>>, $FutureProvider<List<McpGrant>> {
  /// Grants for the open pane, read again each time the pane is shown.
  McpGrantsProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noMcpRetry,
        name: r'mcpGrantsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpGrantsHash();

  @$internal
  @override
  $FutureProviderElement<List<McpGrant>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<McpGrant>> create(Ref ref) {
    return mcpGrants(ref);
  }
}

String _$mcpGrantsHash() => r'afe7dcb0ab6755c84dc5c0a015d749a7a197982d';
