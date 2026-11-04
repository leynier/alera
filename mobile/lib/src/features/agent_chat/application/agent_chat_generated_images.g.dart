// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_generated_images.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The image an `image_generation` item saved on the host
/// (`agentChatGeneratedImagesV1`), read in pieces through the relay. Kept a
/// minute after its last reader, so scrolling back does not read it again.

@ProviderFor(agentChatGeneratedImage)
final agentChatGeneratedImageProvider = AgentChatGeneratedImageFamily._();

/// The image an `image_generation` item saved on the host
/// (`agentChatGeneratedImagesV1`), read in pieces through the relay. Kept a
/// minute after its last reader, so scrolling back does not read it again.

final class AgentChatGeneratedImageProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatGeneratedImage>,
          AgentChatGeneratedImage,
          FutureOr<AgentChatGeneratedImage>
        >
    with
        $FutureModifier<AgentChatGeneratedImage>,
        $FutureProvider<AgentChatGeneratedImage> {
  /// The image an `image_generation` item saved on the host
  /// (`agentChatGeneratedImagesV1`), read in pieces through the relay. Kept a
  /// minute after its last reader, so scrolling back does not read it again.
  AgentChatGeneratedImageProvider._({
    required AgentChatGeneratedImageFamily super.from,
    required (String, String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'agentChatGeneratedImageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentChatGeneratedImageHash();

  @override
  String toString() {
    return r'agentChatGeneratedImageProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatGeneratedImage> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatGeneratedImage> create(Ref ref) {
    final argument = this.argument as (String, String, String, String);
    return agentChatGeneratedImage(
      ref,
      argument.$1,
      argument.$2,
      argument.$3,
      argument.$4,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentChatGeneratedImageProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentChatGeneratedImageHash() =>
    r'9f1ecac4ea443023f47f74c487b03a35376cfb6d';

/// The image an `image_generation` item saved on the host
/// (`agentChatGeneratedImagesV1`), read in pieces through the relay. Kept a
/// minute after its last reader, so scrolling back does not read it again.

final class AgentChatGeneratedImageFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatGeneratedImage>,
          (String, String, String, String)
        > {
  AgentChatGeneratedImageFamily._()
    : super(
        retry: null,
        name: r'agentChatGeneratedImageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The image an `image_generation` item saved on the host
  /// (`agentChatGeneratedImagesV1`), read in pieces through the relay. Kept a
  /// minute after its last reader, so scrolling back does not read it again.

  AgentChatGeneratedImageProvider call(
    String hostId,
    String workspaceId,
    String chatId,
    String itemId,
  ) => AgentChatGeneratedImageProvider._(
    argument: (hostId, workspaceId, chatId, itemId),
    from: this,
  );

  @override
  String toString() => r'agentChatGeneratedImageProvider';
}
