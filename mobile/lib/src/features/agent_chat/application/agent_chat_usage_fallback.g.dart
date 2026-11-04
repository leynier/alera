// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_usage_fallback.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The quota readings of [hostId] the phone already fetched, or none while
/// they load or fail. New Chat never waits for them.

@ProviderFor(agentChatUsageReadings)
final agentChatUsageReadingsProvider = AgentChatUsageReadingsFamily._();

/// The quota readings of [hostId] the phone already fetched, or none while
/// they load or fail. New Chat never waits for them.

final class AgentChatUsageReadingsProvider
    extends
        $FunctionalProvider<
          List<AgentChatUsageReading>,
          List<AgentChatUsageReading>,
          List<AgentChatUsageReading>
        >
    with $Provider<List<AgentChatUsageReading>> {
  /// The quota readings of [hostId] the phone already fetched, or none while
  /// they load or fail. New Chat never waits for them.
  AgentChatUsageReadingsProvider._({
    required AgentChatUsageReadingsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentChatUsageReadingsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatUsageReadingsHash();

  @override
  String toString() {
    return r'agentChatUsageReadingsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<AgentChatUsageReading>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<AgentChatUsageReading> create(Ref ref) {
    final argument = this.argument as String;
    return agentChatUsageReadings(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AgentChatUsageReading> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AgentChatUsageReading>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatUsageReadingsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatUsageReadingsHash() =>
    r'2c31d748a2242a1a56b8866d237890bcb99a49fd';

/// The quota readings of [hostId] the phone already fetched, or none while
/// they load or fail. New Chat never waits for them.

final class AgentChatUsageReadingsFamily extends $Family
    with $FunctionalFamilyOverride<List<AgentChatUsageReading>, String> {
  AgentChatUsageReadingsFamily._()
    : super(
        retry: null,
        name: r'agentChatUsageReadingsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The quota readings of [hostId] the phone already fetched, or none while
  /// they load or fail. New Chat never waits for them.

  AgentChatUsageReadingsProvider call(String hostId) =>
      AgentChatUsageReadingsProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentChatUsageReadingsProvider';
}

/// The notice of each new chat that started on another agent because the
/// default one was out of usage, by [agentChatUsageFallbackKey], until
/// dismissed.

@ProviderFor(AgentChatUsageFallbacks)
final agentChatUsageFallbacksProvider = AgentChatUsageFallbacksProvider._();

/// The notice of each new chat that started on another agent because the
/// default one was out of usage, by [agentChatUsageFallbackKey], until
/// dismissed.
final class AgentChatUsageFallbacksProvider
    extends
        $NotifierProvider<
          AgentChatUsageFallbacks,
          Map<String, AgentChatUsageFallback>
        > {
  /// The notice of each new chat that started on another agent because the
  /// default one was out of usage, by [agentChatUsageFallbackKey], until
  /// dismissed.
  AgentChatUsageFallbacksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatUsageFallbacksProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatUsageFallbacksHash();

  @$internal
  @override
  AgentChatUsageFallbacks create() => AgentChatUsageFallbacks();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AgentChatUsageFallback> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AgentChatUsageFallback>>(
        value,
      ),
    );
  }
}

String _$agentChatUsageFallbacksHash() =>
    r'e3a1564e9accc8b19d12251039bf6b08ac4fa65e';

/// The notice of each new chat that started on another agent because the
/// default one was out of usage, by [agentChatUsageFallbackKey], until
/// dismissed.

abstract class _$AgentChatUsageFallbacks
    extends $Notifier<Map<String, AgentChatUsageFallback>> {
  Map<String, AgentChatUsageFallback> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, AgentChatUsageFallback>,
              Map<String, AgentChatUsageFallback>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, AgentChatUsageFallback>,
                Map<String, AgentChatUsageFallback>
              >,
              Map<String, AgentChatUsageFallback>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
