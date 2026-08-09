part of 'codex_chat_surface.dart';

extension _CodexPlanActions on _CodexChatSurfaceState {
  Future<void> _preparePlanDecision() async {
    await _timelineViewKey.currentState?.restorePlanAndWait();
    if (!mounted) return;
    _planDecisionRevision.value++;
  }

  void _notifyPlanDecision() => unawaited(_preparePlanDecision());

  Future<void> _submitQuestions(
    CodexChatController controller,
    CodexPendingRequest request,
    Map<String, List<String>> answers,
  ) async {
    if (request.isImplementPlanQuestion) await _preparePlanDecision();
    await controller.submitQuestions(request, answers);
  }

  Future<void> _implementPlan(CodexChatController controller) async {
    await _preparePlanDecision();
    await controller.implementPlan();
  }

  Future<void> _declinePlan(CodexChatController controller) async {
    await _preparePlanDecision();
    await controller.declinePlan();
  }

  Future<void> _refinePlan(
    CodexChatController controller,
    String refinement,
  ) async {
    await _preparePlanDecision();
    await controller.refinePlan(refinement);
  }
}
