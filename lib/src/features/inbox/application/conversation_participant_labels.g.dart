// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_participant_labels.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Readable names for terminal handles: the tab title and agent the sidebar
/// knows. A handle missing from the sidebar keeps its raw id.

@ProviderFor(conversationParticipantLabels)
final conversationParticipantLabelsProvider =
    ConversationParticipantLabelsProvider._();

/// Readable names for terminal handles: the tab title and agent the sidebar
/// knows. A handle missing from the sidebar keeps its raw id.

final class ConversationParticipantLabelsProvider
    extends
        $FunctionalProvider<
          Map<String, String>,
          Map<String, String>,
          Map<String, String>
        >
    with $Provider<Map<String, String>> {
  /// Readable names for terminal handles: the tab title and agent the sidebar
  /// knows. A handle missing from the sidebar keeps its raw id.
  ConversationParticipantLabelsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'conversationParticipantLabelsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$conversationParticipantLabelsHash();

  @$internal
  @override
  $ProviderElement<Map<String, String>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, String> create(Ref ref) {
    return conversationParticipantLabels(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, String>>(value),
    );
  }
}

String _$conversationParticipantLabelsHash() =>
    r'b8bfb986609405bbf58bf79b090997ea8342ffe8';

/// Workspace names by id, for the conversation filter and rows.

@ProviderFor(conversationWorkspaceNames)
final conversationWorkspaceNamesProvider =
    ConversationWorkspaceNamesProvider._();

/// Workspace names by id, for the conversation filter and rows.

final class ConversationWorkspaceNamesProvider
    extends
        $FunctionalProvider<
          Map<String, String>,
          Map<String, String>,
          Map<String, String>
        >
    with $Provider<Map<String, String>> {
  /// Workspace names by id, for the conversation filter and rows.
  ConversationWorkspaceNamesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'conversationWorkspaceNamesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$conversationWorkspaceNamesHash();

  @$internal
  @override
  $ProviderElement<Map<String, String>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, String> create(Ref ref) {
    return conversationWorkspaceNames(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, String>>(value),
    );
  }
}

String _$conversationWorkspaceNamesHash() =>
    r'a7007cc48e8b0c773776a1332928963b9c8d8edd';
