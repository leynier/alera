// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_usage_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentUsage)
final agentUsageProvider = AgentUsageFamily._();

final class AgentUsageProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentUsageSnapshot>,
          AgentUsageSnapshot,
          FutureOr<AgentUsageSnapshot>
        >
    with
        $FutureModifier<AgentUsageSnapshot>,
        $FutureProvider<AgentUsageSnapshot> {
  AgentUsageProvider._({
    required AgentUsageFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'agentUsageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentUsageHash();

  @override
  String toString() {
    return r'agentUsageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AgentUsageSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentUsageSnapshot> create(Ref ref) {
    final argument = this.argument as int;
    return agentUsage(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentUsageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentUsageHash() => r'243f4df52a12a6e906cb90ec2752527a30890b7d';

final class AgentUsageFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AgentUsageSnapshot>, int> {
  AgentUsageFamily._()
    : super(
        retry: null,
        name: r'agentUsageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentUsageProvider call(int days) =>
      AgentUsageProvider._(argument: days, from: this);

  @override
  String toString() => r'agentUsageProvider';
}
