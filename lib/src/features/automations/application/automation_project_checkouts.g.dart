// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_project_checkouts.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(automationProjectCheckouts)
final automationProjectCheckoutsProvider = AutomationProjectCheckoutsFamily._();

final class AutomationProjectCheckoutsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<({String hostId, String path})>>,
          List<({String hostId, String path})>,
          FutureOr<List<({String hostId, String path})>>
        >
    with
        $FutureModifier<List<({String hostId, String path})>>,
        $FutureProvider<List<({String hostId, String path})>> {
  AutomationProjectCheckoutsProvider._({
    required AutomationProjectCheckoutsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'automationProjectCheckoutsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$automationProjectCheckoutsHash();

  @override
  String toString() {
    return r'automationProjectCheckoutsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<({String hostId, String path})>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<({String hostId, String path})>> create(Ref ref) {
    final argument = this.argument as String;
    return automationProjectCheckouts(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AutomationProjectCheckoutsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$automationProjectCheckoutsHash() =>
    r'37c54d4e6de14ae9916c03da31a9255daf873705';

final class AutomationProjectCheckoutsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<({String hostId, String path})>>,
          String
        > {
  AutomationProjectCheckoutsFamily._()
    : super(
        retry: null,
        name: r'automationProjectCheckoutsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AutomationProjectCheckoutsProvider call(String projectId) =>
      AutomationProjectCheckoutsProvider._(argument: projectId, from: this);

  @override
  String toString() => r'automationProjectCheckoutsProvider';
}
