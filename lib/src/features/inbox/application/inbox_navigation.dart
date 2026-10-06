import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'inbox_navigation.g.dart';

/// A request to open the composer, optionally with a recipient chosen.
class const InboxComposeRequest({final String? targetHandle});

/// Which half of the inbox page is shown.
enum InboxView { questions, conversations }

class const InboxLocation({
  final bool visible = false,
  final InboxView view = InboxView.questions,
  final String? conversationWorkspace,
  final String? selectedConversationId,
  final String? inboxFilter,
  final InboxQuestionStatus? statusFilter,
  final String? selectedThreadId,
  final InboxComposeRequest? compose,
  final int composeSequence = 0,
}) {
  InboxLocation copyWith({
    bool? visible,
    InboxView? view,
    String? Function()? conversationWorkspace,
    String? Function()? selectedConversationId,
    String? Function()? inboxFilter,
    InboxQuestionStatus? Function()? statusFilter,
    String? Function()? selectedThreadId,
    InboxComposeRequest? Function()? compose,
    int? composeSequence,
  }) => InboxLocation(
    visible: visible ?? this.visible,
    view: view ?? this.view,
    conversationWorkspace: conversationWorkspace == null
        ? this.conversationWorkspace
        : conversationWorkspace(),
    selectedConversationId: selectedConversationId == null
        ? this.selectedConversationId
        : selectedConversationId(),
    inboxFilter: inboxFilter == null ? this.inboxFilter : inboxFilter(),
    statusFilter: statusFilter == null ? this.statusFilter : statusFilter(),
    selectedThreadId: selectedThreadId == null
        ? this.selectedThreadId
        : selectedThreadId(),
    compose: compose == null ? this.compose : compose(),
    composeSequence: composeSequence ?? this.composeSequence,
  );
}

// Retain only navigation, never runtime snapshots or subscriptions.
@Riverpod(keepAlive: true)
class InboxNavigation extends _$InboxNavigation {
  @override
  InboxLocation build() => const InboxLocation();

  /// The Run Board, Automations and the inbox share the shell's page slot.
  void open() {
    ref.read(runBoardNavigationProvider.notifier).close();
    ref.read(automationsNavigationProvider.notifier).close();
    state = state.copyWith(visible: true);
  }

  void close() => state = state.copyWith(visible: false);

  /// A thread is a question, so selecting one always shows Questions.
  void selectThread(String? threadId) => state = state.copyWith(
    view: InboxView.questions,
    selectedThreadId: () => threadId,
  );

  /// Opens the page on Questions, where replies are read.
  void openQuestions() {
    open();
    state = state.copyWith(view: InboxView.questions);
  }

  void filterInbox(String? inbox) => state = state.copyWith(
    inboxFilter: () => inbox,
    selectedThreadId: () => null,
  );

  void filterStatus(InboxQuestionStatus? status) =>
      state = state.copyWith(statusFilter: () => status);

  /// Opens the page and asks it to show the composer once mounted.
  void compose({String? targetHandle}) {
    openQuestions();
    state = state.copyWith(
      compose: () => InboxComposeRequest(targetHandle: targetHandle),
      composeSequence: state.composeSequence + 1,
    );
  }

  void consumeCompose() => state = state.copyWith(compose: () => null);

  void showView(InboxView view) => state = state.copyWith(view: view);

  void selectConversation(String? threadId) =>
      state = state.copyWith(selectedConversationId: () => threadId);

  void filterConversationWorkspace(String? workspaceId) =>
      state = state.copyWith(
        conversationWorkspace: () => workspaceId,
        selectedConversationId: () => null,
      );
}
