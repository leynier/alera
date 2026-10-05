// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_workspace_tags.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Workspace tags an automation can give the workspaces its runs create.

@ProviderFor(automationWorkspaceTags)
final automationWorkspaceTagsProvider = AutomationWorkspaceTagsProvider._();

/// Workspace tags an automation can give the workspaces its runs create.

final class AutomationWorkspaceTagsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<WorkspaceTag>>,
          List<WorkspaceTag>,
          FutureOr<List<WorkspaceTag>>
        >
    with
        $FutureModifier<List<WorkspaceTag>>,
        $FutureProvider<List<WorkspaceTag>> {
  /// Workspace tags an automation can give the workspaces its runs create.
  AutomationWorkspaceTagsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationWorkspaceTagsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationWorkspaceTagsHash();

  @$internal
  @override
  $FutureProviderElement<List<WorkspaceTag>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<WorkspaceTag>> create(Ref ref) {
    return automationWorkspaceTags(ref);
  }
}

String _$automationWorkspaceTagsHash() =>
    r'50d09bb953d41cbcc11cf4220395d9d933d0c613';
