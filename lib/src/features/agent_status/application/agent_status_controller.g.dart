// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_status_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentStatusClock)
final agentStatusClockProvider = AgentStatusClockProvider._();

final class AgentStatusClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  AgentStatusClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentStatusClockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentStatusClockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return agentStatusClock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$agentStatusClockHash() => r'059f444eb7325191ada18fd76d4113764ee4e805';

@ProviderFor(agentStatusByTerminalSession)
final agentStatusByTerminalSessionProvider =
    AgentStatusByTerminalSessionFamily._();

final class AgentStatusByTerminalSessionProvider
    extends
        $FunctionalProvider<
          AgentStatusEntry?,
          AgentStatusEntry?,
          AgentStatusEntry?
        >
    with $Provider<AgentStatusEntry?> {
  AgentStatusByTerminalSessionProvider._({
    required AgentStatusByTerminalSessionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentStatusByTerminalSessionProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentStatusByTerminalSessionHash();

  @override
  String toString() {
    return r'agentStatusByTerminalSessionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AgentStatusEntry?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentStatusEntry? create(Ref ref) {
    final argument = this.argument as String;
    return agentStatusByTerminalSession(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentStatusEntry? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentStatusEntry?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentStatusByTerminalSessionProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentStatusByTerminalSessionHash() =>
    r'b03b0ec888d9c8094b3f765025c88462d09cb955';

final class AgentStatusByTerminalSessionFamily extends $Family
    with $FunctionalFamilyOverride<AgentStatusEntry?, String> {
  AgentStatusByTerminalSessionFamily._()
    : super(
        retry: null,
        name: r'agentStatusByTerminalSessionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  AgentStatusByTerminalSessionProvider call(String terminalSessionId) =>
      AgentStatusByTerminalSessionProvider._(
        argument: terminalSessionId,
        from: this,
      );

  @override
  String toString() => r'agentStatusByTerminalSessionProvider';
}

@ProviderFor(AgentStatusController)
final agentStatusControllerProvider = AgentStatusControllerProvider._();

final class AgentStatusControllerProvider
    extends
        $NotifierProvider<
          AgentStatusController,
          Map<String, AgentStatusEntry>
        > {
  AgentStatusControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentStatusControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentStatusControllerHash();

  @$internal
  @override
  AgentStatusController create() => AgentStatusController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AgentStatusEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AgentStatusEntry>>(
        value,
      ),
    );
  }
}

String _$agentStatusControllerHash() =>
    r'9423dc65a6d812e8896c82c264f5a4a795628623';

abstract class _$AgentStatusController
    extends $Notifier<Map<String, AgentStatusEntry>> {
  Map<String, AgentStatusEntry> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, AgentStatusEntry>,
              Map<String, AgentStatusEntry>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, AgentStatusEntry>,
                Map<String, AgentStatusEntry>
              >,
              Map<String, AgentStatusEntry>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
