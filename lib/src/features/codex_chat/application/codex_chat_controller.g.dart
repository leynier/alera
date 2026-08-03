// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'codex_chat_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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
    r'e66a069bce126c77b79016c08f4495ead7f6681d';

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
