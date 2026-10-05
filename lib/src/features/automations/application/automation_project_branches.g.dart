// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_project_branches.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(automationProjectBranches)
final automationProjectBranchesProvider = AutomationProjectBranchesFamily._();

final class AutomationProjectBranchesProvider
    extends
        $FunctionalProvider<
          AsyncValue<AutomationProjectBranches>,
          AutomationProjectBranches,
          FutureOr<AutomationProjectBranches>
        >
    with
        $FutureModifier<AutomationProjectBranches>,
        $FutureProvider<AutomationProjectBranches> {
  AutomationProjectBranchesProvider._({
    required AutomationProjectBranchesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'automationProjectBranchesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$automationProjectBranchesHash();

  @override
  String toString() {
    return r'automationProjectBranchesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AutomationProjectBranches> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AutomationProjectBranches> create(Ref ref) {
    final argument = this.argument as String;
    return automationProjectBranches(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AutomationProjectBranchesProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$automationProjectBranchesHash() =>
    r'3f2986fb3b189849402e5c39ac906960753f5728';

final class AutomationProjectBranchesFamily extends $Family
    with
        $FunctionalFamilyOverride<FutureOr<AutomationProjectBranches>, String> {
  AutomationProjectBranchesFamily._()
    : super(
        retry: null,
        name: r'automationProjectBranchesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AutomationProjectBranchesProvider call(String projectId) =>
      AutomationProjectBranchesProvider._(argument: projectId, from: this);

  @override
  String toString() => r'automationProjectBranchesProvider';
}
