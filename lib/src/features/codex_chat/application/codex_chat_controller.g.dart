// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'codex_chat_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(codexChatRuntimeClient)
final codexChatRuntimeClientProvider = CodexChatRuntimeClientProvider._();

final class CodexChatRuntimeClientProvider
    extends
        $FunctionalProvider<
          RuntimeHostClient,
          RuntimeHostClient,
          RuntimeHostClient
        >
    with $Provider<RuntimeHostClient> {
  CodexChatRuntimeClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'codexChatRuntimeClientProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$codexChatRuntimeClientHash();

  @$internal
  @override
  $ProviderElement<RuntimeHostClient> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeHostClient create(Ref ref) {
    return codexChatRuntimeClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeHostClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeHostClient>(value),
    );
  }
}

String _$codexChatRuntimeClientHash() =>
    r'3d83da5bd040031693f5fa809a9ed04a332c97ae';

@ProviderFor(CodexChatController)
final codexChatControllerProvider = CodexChatControllerFamily._();

final class CodexChatControllerProvider
    extends $NotifierProvider<CodexChatController, CodexChatState> {
  CodexChatControllerProvider._({
    required CodexChatControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'codexChatControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$codexChatControllerHash();

  @override
  String toString() {
    return r'codexChatControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CodexChatController create() => CodexChatController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CodexChatState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CodexChatState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CodexChatControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$codexChatControllerHash() =>
    r'9f6f49679ba2e41a2a7c8d47e2b801213a04d6b9';

final class CodexChatControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          CodexChatController,
          CodexChatState,
          CodexChatState,
          CodexChatState,
          String
        > {
  CodexChatControllerFamily._()
    : super(
        retry: null,
        name: r'codexChatControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CodexChatControllerProvider call(String tabId) =>
      CodexChatControllerProvider._(argument: tabId, from: this);

  @override
  String toString() => r'codexChatControllerProvider';
}

abstract class _$CodexChatController extends $Notifier<CodexChatState> {
  late final _$args = ref.$arg as String;
  String get tabId => _$args;

  CodexChatState build(String tabId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CodexChatState, CodexChatState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CodexChatState, CodexChatState>,
              CodexChatState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
