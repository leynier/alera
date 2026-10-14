// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_chat_attachment_preparation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentChatPrepareAttachments)
final agentChatPrepareAttachmentsProvider =
    AgentChatPrepareAttachmentsProvider._();

final class AgentChatPrepareAttachmentsProvider
    extends
        $FunctionalProvider<
          AgentChatPrepareAttachments,
          AgentChatPrepareAttachments,
          AgentChatPrepareAttachments
        >
    with $Provider<AgentChatPrepareAttachments> {
  AgentChatPrepareAttachmentsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentChatPrepareAttachmentsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentChatPrepareAttachmentsHash();

  @$internal
  @override
  $ProviderElement<AgentChatPrepareAttachments> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatPrepareAttachments create(Ref ref) {
    return agentChatPrepareAttachments(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatPrepareAttachments value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatPrepareAttachments>(value),
    );
  }
}

String _$agentChatPrepareAttachmentsHash() =>
    r'05e1c0fd9e22cefd49d6391fe2fa0180687346d3';
