import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';

class const AgentChatQuestionOption({
  required final String label,
  final String description = '',
  final String? value,
}) {
  factory fromJson(Object? json) {
    if (json is String) return AgentChatQuestionOption(label: json);
    final map = agentChatJsonMap(json);
    return AgentChatQuestionOption(
      label: agentChatJsonText(map['label']),
      description: agentChatJsonText(map['description']),
      value: agentChatJsonString(map['value']),
    );
  }

  /// What an answer carries for this option: the provider's value when it
  /// gave one, otherwise the label it showed.
  String get answerValue => value ?? label;
}

class const AgentChatQuestion({
  required final String id,
  required final String question,
  final String header = '',
  final List<AgentChatQuestionOption> options =
      const <AgentChatQuestionOption>[],
  final bool allowCustomAnswer = false,
  final String? initialAnswer,
  final bool multiSelect = false,
  final bool secret = false,
}) {
  factory fromJson(Object? value, {int index = 0}) {
    final json = agentChatJsonMap(value);
    final options = <AgentChatQuestionOption>[
      for (final option in agentChatJsonList(json['options']))
        AgentChatQuestionOption.fromJson(option),
    ];
    return AgentChatQuestion(
      id: agentChatJsonString(json['id']) ?? 'question-$index',
      header: agentChatJsonText(json['header']),
      question:
          agentChatJsonString(json['question']) ??
          agentChatJsonString(json['header']) ??
          'The agent asked a question.',
      options: options,
      // A question without options can only be answered in free text.
      allowCustomAnswer:
          agentChatJsonBool(json['allowCustomAnswer']) || options.isEmpty,
      initialAnswer: agentChatJsonString(json['initialAnswer']),
      multiSelect: agentChatJsonBool(json['multiSelect']),
      secret: agentChatJsonBool(json['secret']),
    );
  }
}

class const AgentChatElicitation({
  required final String mode,
  final String message = '',
  final AgentChatJson schema = const <String, Object?>{},
  final String? url,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatElicitation(
      mode: agentChatJsonText(json['mode']),
      message: agentChatJsonText(json['message']),
      schema: agentChatJsonMap(json['schema']),
      url: agentChatJsonString(json['url']),
    );
  }

  AgentChatJson get properties => agentChatJsonMap(schema['properties']);

  Set<String> get requiredFields =>
      agentChatJsonStringList(schema['required']).toSet();

  /// Flat forms of string, number, integer and boolean fields are the only
  /// shape the apps render; anything richer is declined or cancelled.
  bool get hasSupportedForm =>
      properties.isNotEmpty &&
      properties.values.every((property) {
        final field = agentChatJsonMap(property);
        final type = agentChatJsonString(field['type']);
        return type == null ||
            type == 'string' ||
            type == 'number' ||
            type == 'integer' ||
            type == 'boolean';
      });
}

/// Why a session with full access still asked for approval.
enum AgentChatFullAccessOverride(this.wire) {
  /// A user-configured ask rule matched.
  askRule('ask_rule'),

  /// The provider's own safety check asked.
  providerCheck('provider_check');

  final String wire;

  static AgentChatFullAccessOverride? tryParse(Object? value) {
    for (final override in values) {
      if (override.wire == value) return override;
    }
    return null;
  }
}

/// Something the agent is waiting on: an approval, answers to questions, or
/// an MCP server form. [id] is the runtime's request id, which is what a
/// response must name; the provider's native id never reaches the client.
class const AgentChatRequest({
  required final String id,
  required final AgentChatRequestKind kind,
  required final DateTime createdAt,
  final String? turnId,
  final String? itemId,
  final String? title,
  final String? detail,
  final String? command,
  final String? cwd,
  final String? path,
  final List<AgentChatQuestion> questions = const <AgentChatQuestion>[],
  final List<AgentChatApprovalDecision> decisions =
      const <AgentChatApprovalDecision>[],
  final AgentChatElicitation? elicitation,
  final DateTime? expiresAt,
  final AgentChatJson payload = const <String, Object?>{},
  final bool supportsFeedback = false,
  final AgentChatFullAccessOverride? fullAccessOverride,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(json['requestId'] ?? json['id']);
    if (id == null) {
      throw const FormatException('Agent chat request has no requestId.');
    }
    final questions = agentChatJsonList(json['questions']);
    final elicitation = json['elicitation'];
    return AgentChatRequest(
      id: id,
      kind: AgentChatRequestKind.fromJson(json['kind']),
      createdAt:
          agentChatJsonDate(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      turnId: agentChatJsonString(json['turnId']),
      itemId: agentChatJsonString(json['itemId']),
      title: agentChatJsonString(json['title']),
      detail: agentChatJsonString(json['detail']),
      command: agentChatJsonString(json['command']),
      cwd: agentChatJsonString(json['cwd']),
      path: agentChatJsonString(json['path']),
      questions: <AgentChatQuestion>[
        for (var index = 0; index < questions.length; index += 1)
          AgentChatQuestion.fromJson(questions[index], index: index),
      ],
      decisions: <AgentChatApprovalDecision>[
        for (final decision in agentChatJsonList(json['decisions']))
          ?AgentChatApprovalDecision.tryParse(decision),
      ],
      elicitation: elicitation is Map
          ? AgentChatElicitation.fromJson(elicitation)
          : null,
      expiresAt: agentChatJsonDate(json['expiresAt']),
      payload: agentChatJsonMap(json['payload']),
      supportsFeedback: agentChatJsonBool(json['supportsFeedback']),
      fullAccessOverride: AgentChatFullAccessOverride.tryParse(
        json['fullAccessOverride'],
      ),
    );
  }

  bool get isQuestion => kind.isUserInput && questions.isNotEmpty;

  bool get isApproval => kind.isApproval;

  bool get isElicitation => kind.isElicitation;

  /// Decisions offered by the runtime. An approval that names none still lets
  /// the user allow or decline, which every approval-capable provider honors.
  List<AgentChatApprovalDecision> get offeredDecisions => decisions.isNotEmpty
      ? decisions
      : const <AgentChatApprovalDecision>[
          AgentChatApprovalDecision.accept,
          AgentChatApprovalDecision.decline,
        ];
}
