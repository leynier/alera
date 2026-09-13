// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_control_branches.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Branches for the branch sheet, loaded each time the sheet opens.

@ProviderFor(sourceControlBranches)
final sourceControlBranchesProvider = SourceControlBranchesFamily._();

/// Branches for the branch sheet, loaded each time the sheet opens.

final class SourceControlBranchesProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileGitBranches>,
          MobileGitBranches,
          FutureOr<MobileGitBranches>
        >
    with
        $FutureModifier<MobileGitBranches>,
        $FutureProvider<MobileGitBranches> {
  /// Branches for the branch sheet, loaded each time the sheet opens.
  SourceControlBranchesProvider._({
    required SourceControlBranchesFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'sourceControlBranchesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sourceControlBranchesHash();

  @override
  String toString() {
    return r'sourceControlBranchesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<MobileGitBranches> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileGitBranches> create(Ref ref) {
    final argument = this.argument as (String, String);
    return sourceControlBranches(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is SourceControlBranchesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sourceControlBranchesHash() =>
    r'd74f0e5bfcd9f9c33e32e5a06e461055db4b877f';

/// Branches for the branch sheet, loaded each time the sheet opens.

final class SourceControlBranchesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<MobileGitBranches>,
          (String, String)
        > {
  SourceControlBranchesFamily._()
    : super(
        retry: null,
        name: r'sourceControlBranchesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Branches for the branch sheet, loaded each time the sheet opens.

  SourceControlBranchesProvider call(String hostId, String workspaceId) =>
      SourceControlBranchesProvider._(
        argument: (hostId, workspaceId),
        from: this,
      );

  @override
  String toString() => r'sourceControlBranchesProvider';
}
