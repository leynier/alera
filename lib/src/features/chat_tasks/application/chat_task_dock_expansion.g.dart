// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_task_dock_expansion.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Which chats show their Tasks dock expanded. Session state, so a tab switch
/// keeps it and a restart starts collapsed.

@ProviderFor(ChatTaskDockExpansion)
final chatTaskDockExpansionProvider = ChatTaskDockExpansionProvider._();

/// Which chats show their Tasks dock expanded. Session state, so a tab switch
/// keeps it and a restart starts collapsed.
final class ChatTaskDockExpansionProvider
    extends $NotifierProvider<ChatTaskDockExpansion, Set<String>> {
  /// Which chats show their Tasks dock expanded. Session state, so a tab switch
  /// keeps it and a restart starts collapsed.
  ChatTaskDockExpansionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatTaskDockExpansionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatTaskDockExpansionHash();

  @$internal
  @override
  ChatTaskDockExpansion create() => ChatTaskDockExpansion();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$chatTaskDockExpansionHash() =>
    r'da68e225969531bff2e91392acddaac597e80217';

/// Which chats show their Tasks dock expanded. Session state, so a tab switch
/// keeps it and a restart starts collapsed.

abstract class _$ChatTaskDockExpansion extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
