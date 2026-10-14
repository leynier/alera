// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_provider_settings_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentProviderSettingsSupport)
final agentProviderSettingsSupportProvider =
    AgentProviderSettingsSupportProvider._();

final class AgentProviderSettingsSupportProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentProviderSettingsSupport>,
          AgentProviderSettingsSupport,
          FutureOr<AgentProviderSettingsSupport>
        >
    with
        $FutureModifier<AgentProviderSettingsSupport>,
        $FutureProvider<AgentProviderSettingsSupport> {
  AgentProviderSettingsSupportProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentProviderSettingsSupportProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentProviderSettingsSupportHash();

  @$internal
  @override
  $FutureProviderElement<AgentProviderSettingsSupport> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentProviderSettingsSupport> create(Ref ref) {
    return agentProviderSettingsSupport(ref);
  }
}

String _$agentProviderSettingsSupportHash() =>
    r'a8530294f02d0442669a0be217e9a74186782754';

/// The provider catalog of one host, as Settings shows it. [hostId] is null
/// for This Device. Reads come from the host's status cache; [refresh] forces
/// a re-check.

@ProviderFor(AgentProviderCatalogController)
final agentProviderCatalogControllerProvider =
    AgentProviderCatalogControllerFamily._();

/// The provider catalog of one host, as Settings shows it. [hostId] is null
/// for This Device. Reads come from the host's status cache; [refresh] forces
/// a re-check.
final class AgentProviderCatalogControllerProvider
    extends
        $AsyncNotifierProvider<
          AgentProviderCatalogController,
          AgentProviderCatalogState
        > {
  /// The provider catalog of one host, as Settings shows it. [hostId] is null
  /// for This Device. Reads come from the host's status cache; [refresh] forces
  /// a re-check.
  AgentProviderCatalogControllerProvider._({
    required AgentProviderCatalogControllerFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'agentProviderCatalogControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentProviderCatalogControllerHash();

  @override
  String toString() {
    return r'agentProviderCatalogControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentProviderCatalogController create() => AgentProviderCatalogController();

  @override
  bool operator ==(Object other) {
    return other is AgentProviderCatalogControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentProviderCatalogControllerHash() =>
    r'f68e7d4e05cc7d5a209db563b2e91b9c9d2994c4';

/// The provider catalog of one host, as Settings shows it. [hostId] is null
/// for This Device. Reads come from the host's status cache; [refresh] forces
/// a re-check.

final class AgentProviderCatalogControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentProviderCatalogController,
          AsyncValue<AgentProviderCatalogState>,
          AgentProviderCatalogState,
          FutureOr<AgentProviderCatalogState>,
          String?
        > {
  AgentProviderCatalogControllerFamily._()
    : super(
        retry: null,
        name: r'agentProviderCatalogControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The provider catalog of one host, as Settings shows it. [hostId] is null
  /// for This Device. Reads come from the host's status cache; [refresh] forces
  /// a re-check.

  AgentProviderCatalogControllerProvider call(String? hostId) =>
      AgentProviderCatalogControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentProviderCatalogControllerProvider';
}

/// The provider catalog of one host, as Settings shows it. [hostId] is null
/// for This Device. Reads come from the host's status cache; [refresh] forces
/// a re-check.

abstract class _$AgentProviderCatalogController
    extends $AsyncNotifier<AgentProviderCatalogState> {
  late final _$args = ref.$arg as String?;
  String? get hostId => _$args;

  FutureOr<AgentProviderCatalogState> build(String? hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AgentProviderCatalogState>,
              AgentProviderCatalogState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AgentProviderCatalogState>,
                AgentProviderCatalogState
              >,
              AsyncValue<AgentProviderCatalogState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The stored provider instances of one host and the writes against them.

@ProviderFor(AgentProviderSettingsController)
final agentProviderSettingsControllerProvider =
    AgentProviderSettingsControllerFamily._();

/// The stored provider instances of one host and the writes against them.
final class AgentProviderSettingsControllerProvider
    extends
        $AsyncNotifierProvider<
          AgentProviderSettingsController,
          AgentChatProviderSettingsSnapshot
        > {
  /// The stored provider instances of one host and the writes against them.
  AgentProviderSettingsControllerProvider._({
    required AgentProviderSettingsControllerFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'agentProviderSettingsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentProviderSettingsControllerHash();

  @override
  String toString() {
    return r'agentProviderSettingsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentProviderSettingsController create() => AgentProviderSettingsController();

  @override
  bool operator ==(Object other) {
    return other is AgentProviderSettingsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentProviderSettingsControllerHash() =>
    r'b03cc054d9720df68988099fc338e1238e85b712';

/// The stored provider instances of one host and the writes against them.

final class AgentProviderSettingsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentProviderSettingsController,
          AsyncValue<AgentChatProviderSettingsSnapshot>,
          AgentChatProviderSettingsSnapshot,
          FutureOr<AgentChatProviderSettingsSnapshot>,
          String?
        > {
  AgentProviderSettingsControllerFamily._()
    : super(
        retry: null,
        name: r'agentProviderSettingsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The stored provider instances of one host and the writes against them.

  AgentProviderSettingsControllerProvider call(String? hostId) =>
      AgentProviderSettingsControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentProviderSettingsControllerProvider';
}

/// The stored provider instances of one host and the writes against them.

abstract class _$AgentProviderSettingsController
    extends $AsyncNotifier<AgentChatProviderSettingsSnapshot> {
  late final _$args = ref.$arg as String?;
  String? get hostId => _$args;

  FutureOr<AgentChatProviderSettingsSnapshot> build(String? hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AgentChatProviderSettingsSnapshot>,
              AgentChatProviderSettingsSnapshot
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AgentChatProviderSettingsSnapshot>,
                AgentChatProviderSettingsSnapshot
              >,
              AsyncValue<AgentChatProviderSettingsSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(agentProviderPreferencesWriter)
final agentProviderPreferencesWriterProvider =
    AgentProviderPreferencesWriterFamily._();

final class AgentProviderPreferencesWriterProvider
    extends
        $FunctionalProvider<
          AgentProviderPreferencesWriter,
          AgentProviderPreferencesWriter,
          AgentProviderPreferencesWriter
        >
    with $Provider<AgentProviderPreferencesWriter> {
  AgentProviderPreferencesWriterProvider._({
    required AgentProviderPreferencesWriterFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'agentProviderPreferencesWriterProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentProviderPreferencesWriterHash();

  @override
  String toString() {
    return r'agentProviderPreferencesWriterProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AgentProviderPreferencesWriter> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentProviderPreferencesWriter create(Ref ref) {
    final argument = this.argument as String?;
    return agentProviderPreferencesWriter(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentProviderPreferencesWriter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentProviderPreferencesWriter>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentProviderPreferencesWriterProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentProviderPreferencesWriterHash() =>
    r'9a78cf51ada80069008934e14900fca56c4d71be';

final class AgentProviderPreferencesWriterFamily extends $Family
    with $FunctionalFamilyOverride<AgentProviderPreferencesWriter, String?> {
  AgentProviderPreferencesWriterFamily._()
    : super(
        retry: null,
        name: r'agentProviderPreferencesWriterProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentProviderPreferencesWriterProvider call(String? hostId) =>
      AgentProviderPreferencesWriterProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentProviderPreferencesWriterProvider';
}
