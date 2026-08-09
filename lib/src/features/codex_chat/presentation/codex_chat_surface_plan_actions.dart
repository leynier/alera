part of 'codex_chat_surface.dart';

extension _CodexPlanActions on _CodexChatSurfaceState {
  void _notifyPlanDecision() => _planDecisionRevision.value++;

  Future<void> _submitQuestions(
    CodexChatController controller,
    CodexPendingRequest request,
    Map<String, List<String>> answers,
  ) async {
    if (request.isImplementPlanQuestion) _notifyPlanDecision();
    await controller.submitQuestions(request, answers);
  }

  Future<void> _implementPlan(CodexChatController controller) async {
    _notifyPlanDecision();
    await controller.implementPlan();
  }

  Future<void> _declinePlan(CodexChatController controller) async {
    _notifyPlanDecision();
    await controller.declinePlan();
  }

  Future<void> _refinePlan(
    CodexChatController controller,
    String refinement,
  ) async {
    _notifyPlanDecision();
    await controller.refinePlan(refinement);
  }
}
