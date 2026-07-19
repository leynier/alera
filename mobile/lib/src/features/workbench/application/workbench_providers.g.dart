// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workbench_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The workspace surface of the host connection. Tests override this with a
/// fake so workbench controllers can run without a live gateway.

@ProviderFor(workspaceClient)
final workspaceClientProvider = WorkspaceClientFamily._();

/// The workspace surface of the host connection. Tests override this with a
/// fake so workbench controllers can run without a live gateway.

final class WorkspaceClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileWorkspaceClient>,
          MobileWorkspaceClient,
          FutureOr<MobileWorkspaceClient>
        >
    with
        $FutureModifier<MobileWorkspaceClient>,
        $FutureProvider<MobileWorkspaceClient> {
  /// The workspace surface of the host connection. Tests override this with a
  /// fake so workbench controllers can run without a live gateway.
  WorkspaceClientProvider._({
    required WorkspaceClientFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceClientProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceClientHash();

  @override
  String toString() {
    return r'workspaceClientProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileWorkspaceClient> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileWorkspaceClient> create(Ref ref) {
    final argument = this.argument as String;
    return workspaceClient(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceClientProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceClientHash() => r'9090961936ae5bfb9c5391dde4f850b5fbcb396e';

/// The workspace surface of the host connection. Tests override this with a
/// fake so workbench controllers can run without a live gateway.

final class WorkspaceClientFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MobileWorkspaceClient>, String> {
  WorkspaceClientFamily._()
    : super(
        retry: null,
        name: r'workspaceClientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The workspace surface of the host connection. Tests override this with a
  /// fake so workbench controllers can run without a live gateway.

  WorkspaceClientProvider call(String hostId) =>
      WorkspaceClientProvider._(argument: hostId, from: this);

  @override
  String toString() => r'workspaceClientProvider';
}
