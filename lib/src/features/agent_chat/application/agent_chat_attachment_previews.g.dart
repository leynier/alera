// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_attachment_previews.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The bytes of attachment thumbnails read from their host, bounded to
/// [agentChatAttachmentCacheBytes] and kept for the app's life.

@ProviderFor(agentChatAttachmentCache)
final agentChatAttachmentCacheProvider = AgentChatAttachmentCacheProvider._();

/// The bytes of attachment thumbnails read from their host, bounded to
/// [agentChatAttachmentCacheBytes] and kept for the app's life.

final class AgentChatAttachmentCacheProvider
    extends
        $FunctionalProvider<
          AgentChatAttachmentCache,
          AgentChatAttachmentCache,
          AgentChatAttachmentCache
        >
    with $Provider<AgentChatAttachmentCache> {
  /// The bytes of attachment thumbnails read from their host, bounded to
  /// [agentChatAttachmentCacheBytes] and kept for the app's life.
  AgentChatAttachmentCacheProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatAttachmentCacheProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatAttachmentCacheHash();

  @$internal
  @override
  $ProviderElement<AgentChatAttachmentCache> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatAttachmentCache create(Ref ref) {
    return agentChatAttachmentCache(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatAttachmentCache value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatAttachmentCache>(value),
    );
  }
}

String _$agentChatAttachmentCacheHash() =>
    r'64513153d1d82395ee9b214e5092dce6b828b14e';

/// The host's copy of the uploaded image [attachmentId] for a thumbnail on
/// this machine (`agentChatAttachmentReadV1`), or null when the host cannot
/// serve it.

@ProviderFor(agentChatAttachmentPreview)
final agentChatAttachmentPreviewProvider = AgentChatAttachmentPreviewFamily._();

/// The host's copy of the uploaded image [attachmentId] for a thumbnail on
/// this machine (`agentChatAttachmentReadV1`), or null when the host cannot
/// serve it.

final class AgentChatAttachmentPreviewProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatAttachmentBytes?>,
          AgentChatAttachmentBytes?,
          FutureOr<AgentChatAttachmentBytes?>
        >
    with
        $FutureModifier<AgentChatAttachmentBytes?>,
        $FutureProvider<AgentChatAttachmentBytes?> {
  /// The host's copy of the uploaded image [attachmentId] for a thumbnail on
  /// this machine (`agentChatAttachmentReadV1`), or null when the host cannot
  /// serve it.
  AgentChatAttachmentPreviewProvider._({
    required AgentChatAttachmentPreviewFamily super.from,
    required (String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'agentChatAttachmentPreviewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatAttachmentPreviewHash();

  @override
  String toString() {
    return r'agentChatAttachmentPreviewProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatAttachmentBytes?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatAttachmentBytes?> create(Ref ref) {
    final argument = this.argument as (String, String, String);
    return agentChatAttachmentPreview(
      ref,
      argument.$1,
      argument.$2,
      argument.$3,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatAttachmentPreviewProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatAttachmentPreviewHash() =>
    r'f2649ab35356d560f942f3f4fdc5d848af999e61';

/// The host's copy of the uploaded image [attachmentId] for a thumbnail on
/// this machine (`agentChatAttachmentReadV1`), or null when the host cannot
/// serve it.

final class AgentChatAttachmentPreviewFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatAttachmentBytes?>,
          (String, String, String)
        > {
  AgentChatAttachmentPreviewFamily._()
    : super(
        retry: null,
        name: r'agentChatAttachmentPreviewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The host's copy of the uploaded image [attachmentId] for a thumbnail on
  /// this machine (`agentChatAttachmentReadV1`), or null when the host cannot
  /// serve it.

  AgentChatAttachmentPreviewProvider call(
    String chatId,
    String workspaceId,
    String attachmentId,
  ) => AgentChatAttachmentPreviewProvider._(
    argument: (chatId, workspaceId, attachmentId),
    from: this,
  );

  @override
  String toString() => r'agentChatAttachmentPreviewProvider';
}
