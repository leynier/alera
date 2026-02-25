class UserInputOption {
  const UserInputOption({required this.label, required this.description});

  final String label;
  final String description;
}

class UserInputQuestion {
  const UserInputQuestion({
    required this.id,
    required this.header,
    required this.question,
    this.isOther = false,
    this.isSecret = false,
    this.options,
    this.otherLabel,
  });

  final String id;
  final String header;
  final String question;
  final bool isOther;
  final bool isSecret;
  final List<UserInputOption>? options;
  final String? otherLabel;
}

enum PendingUserInputSource { backend, localPlanFallback }

class PendingUserInput {
  const PendingUserInput({
    required this.requestId,
    required this.threadId,
    required this.turnId,
    required this.itemId,
    required this.questions,
    this.source = PendingUserInputSource.backend,
    this.localPlanTurnId,
  });

  final Object requestId;
  final String? threadId;
  final String turnId;
  final String itemId;
  final List<UserInputQuestion> questions;
  final PendingUserInputSource source;
  final String? localPlanTurnId;
}
