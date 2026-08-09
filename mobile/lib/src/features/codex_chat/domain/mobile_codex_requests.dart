part of 'mobile_codex_state.dart';

@immutable
class MobileCodexQuestionOption {
  const MobileCodexQuestionOption({required this.label, this.description});

  factory MobileCodexQuestionOption.fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexQuestionOption(
      label: _first(<Object?>[json['label'], json['value'], value]),
      description: _string(json['description']),
    );
  }

  final String label;
  final String? description;
}

@immutable
class MobileCodexQuestion {
  const MobileCodexQuestion({
    required this.id,
    required this.question,
    this.header,
    this.options = const <MobileCodexQuestionOption>[],
    this.isMultiSelect = false,
    this.isSecret = false,
    this.isOther = false,
  });

  factory MobileCodexQuestion.fromJson(Object? value, {int index = 0}) {
    final json = _map(value);
    return MobileCodexQuestion(
      id: _first(<Object?>[json['id'], json['key'], 'question-$index']),
      question: _first(<Object?>[
        json['question'],
        json['prompt'],
        json['text'],
        'Codex asked a question.',
      ]),
      header: _string(json['header']),
      options: <MobileCodexQuestionOption>[
        if (json['options'] is List)
          for (final option in json['options'] as List)
            MobileCodexQuestionOption.fromJson(option),
      ],
      isMultiSelect:
          json['isMultiSelect'] == true || json['multiSelect'] == true,
      isSecret: json['isSecret'] == true,
      isOther: json['isOther'] == true,
    );
  }

  final String id;
  final String question;
  final String? header;
  final List<MobileCodexQuestionOption> options;
  final bool isMultiSelect;
  final bool isSecret;
  final bool isOther;
}

@immutable
class MobileCodexPendingRequest {
  const MobileCodexPendingRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  factory MobileCodexPendingRequest.fromJson(Object? value) {
    final json = _map(value);
    return MobileCodexPendingRequest(
      id: json['id'] ?? '',
      method: _first(<Object?>[json['method'], 'request']),
      params: _map(json['params']),
    );
  }

  final Object id;
  final String method;
  final Map<String, Object?> params;

  bool get isApproval {
    final lower = method.toLowerCase();
    return lower.contains('approval') ||
        lower.contains('permission') ||
        lower.contains('requestcommand') ||
        lower.contains('requestfile');
  }

  bool get isPermissionsRequest =>
      method.toLowerCase() == 'item/permissions/requestapproval';

  bool get isElicitation =>
      method.toLowerCase() == 'mcpserver/elicitation/request';

  bool get isBlocking {
    final value = params['isBlocking'];
    if (value is bool) return value;
    if (params.containsKey('autoResolutionMs')) return false;
    return true;
  }

  int? get autoResolutionMs => _int(params['autoResolutionMs']);

  String get elicitationMode => _string(params['mode']) ?? '';

  Map<String, Object?> get elicitationSchema => _map(params['requestedSchema']);

  bool get hasSupportedElicitationForm =>
      isElicitation &&
      (elicitationMode == 'form' || elicitationMode == 'openai/form') &&
      elicitationSchema['properties'] is Map &&
      (elicitationSchema['properties'] as Map).values.every((schema) {
        final property = _map(schema);
        final type = _string(property['type']);
        const supportedKeys = <String>{
          'type',
          'title',
          'description',
          'default',
        };
        return property.keys.every(supportedKeys.contains) &&
            (type == null ||
                type == 'string' ||
                type == 'number' ||
                type == 'integer' ||
                type == 'boolean');
      });

  bool get isQuestion {
    final lower = method.toLowerCase();
    return lower.contains('question') ||
        lower.contains('userinput') ||
        lower.contains('request_user_input') ||
        params['questions'] is List;
  }

  List<MobileCodexQuestion> get questions {
    final values = params['questions'];
    if (values is List && values.isNotEmpty) {
      return <MobileCodexQuestion>[
        for (var index = 0; index < values.length; index++)
          MobileCodexQuestion.fromJson(values[index], index: index),
      ];
    }
    return <MobileCodexQuestion>[MobileCodexQuestion.fromJson(params)];
  }

  Set<String> get availableApprovalDecisions {
    final values = params['availableDecisions'];
    if (values is! List) return const <String>{};
    return <String>{
      for (final value in values)
        if (value is String)
          value
        else if (value is Map && value.keys.isNotEmpty)
          value.keys.first.toString(),
    };
  }

  bool supportsApprovalDecision(String decision) {
    if (params['availableDecisions'] is List) {
      return availableApprovalDecisions.contains(decision);
    }
    return switch (decision) {
      'accept' || 'decline' => isApproval,
      'acceptForSession' => _supportsSessionApproval,
      'cancel' => _supportsCancelApproval,
      'acceptWithExecpolicyAmendment' =>
        _isCommandApproval && _proposedExecpolicyAmendment.isNotEmpty,
      'applyNetworkPolicyAmendment' =>
        _isCommandApproval && _proposedNetworkPolicyAmendments.length == 1,
      _ => false,
    };
  }

  Object approvalDecisionValue(String decision) {
    final values = params['availableDecisions'];
    if (values is List) {
      for (final value in values) {
        if (value == decision || value is Map && value.containsKey(decision)) {
          return value!;
        }
      }
    }
    return switch (decision) {
      'acceptWithExecpolicyAmendment'
          when _proposedExecpolicyAmendment.isNotEmpty =>
        <String, Object?>{
          'acceptWithExecpolicyAmendment': <String, Object?>{
            'execpolicy_amendment': _proposedExecpolicyAmendment,
          },
        },
      'applyNetworkPolicyAmendment'
          when _proposedNetworkPolicyAmendments.length == 1 =>
        <String, Object?>{
          'applyNetworkPolicyAmendment': <String, Object?>{
            'network_policy_amendment': _proposedNetworkPolicyAmendments.single,
          },
        },
      _ => decision,
    };
  }

  bool get _isCommandApproval => const <String>{
    'item/commandexecution/requestapproval',
    'execcommandapproval',
  }.contains(method.toLowerCase());

  bool get _supportsSessionApproval => const <String>{
    'item/commandexecution/requestapproval',
    'item/filechange/requestapproval',
    'item/permissions/requestapproval',
    'execcommandapproval',
    'applypatchapproval',
  }.contains(method.toLowerCase());

  bool get _supportsCancelApproval => const <String>{
    'item/commandexecution/requestapproval',
    'item/filechange/requestapproval',
    'execcommandapproval',
    'applypatchapproval',
  }.contains(method.toLowerCase());

  List<Object?> get _proposedExecpolicyAmendment {
    final value =
        params['proposedExecpolicyAmendment'] ??
        params['proposed_execpolicy_amendment'];
    return value is List ? List<Object?>.from(value) : const <Object?>[];
  }

  List<Map<String, Object?>> get _proposedNetworkPolicyAmendments {
    final value =
        params['proposedNetworkPolicyAmendments'] ??
        params['proposed_network_policy_amendments'];
    if (value is! List) return const <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      for (final amendment in value)
        if (amendment is Map) Map<String, Object?>.from(amendment),
    ];
  }

  String approvalDecisionName(Object decision) {
    if (decision is String) return decision;
    if (decision is Map && decision.keys.isNotEmpty) {
      return decision.keys.first.toString();
    }
    return '';
  }

  Object approvalWireDecision(Object decision) {
    final methodName = method.toLowerCase();
    if (methodName != 'execcommandapproval' &&
        methodName != 'applypatchapproval') {
      return decision;
    }
    final decisionName = approvalDecisionName(decision);
    return switch (decisionName) {
      'accept' => 'approved',
      'acceptForSession' => 'approved_for_session',
      'decline' => const <String, Object?>{
        'denied': <String, Object?>{'rejection': 'Denied by user.'},
      },
      'cancel' => 'abort',
      'acceptWithExecpolicyAmendment' => _legacyExecpolicyDecision(decision),
      'applyNetworkPolicyAmendment' => _legacyNetworkDecision(decision),
      _ => decision,
    };
  }

  Object _legacyExecpolicyDecision(Object decision) {
    if (decision is! Map) return decision;
    final value = decision['acceptWithExecpolicyAmendment'];
    if (value is! Map) return decision;
    final amendment = value['execpolicy_amendment'];
    if (amendment is! List) return decision;
    return <String, Object?>{
      'approved_execpolicy_amendment': <String, Object?>{
        'proposed_execpolicy_amendment': amendment,
      },
    };
  }

  Object _legacyNetworkDecision(Object decision) {
    if (decision is! Map) return decision;
    final value = decision['applyNetworkPolicyAmendment'];
    if (value is! Map || value['network_policy_amendment'] == null) {
      return decision;
    }
    return <String, Object?>{
      'network_policy_amendment': <String, Object?>{
        'network_policy_amendment': value['network_policy_amendment'],
      },
    };
  }

  String get description => _first(<Object?>[
    params['reason'],
    params['command'],
    params['path'],
    'Codex is requesting permission to continue.',
  ]);
}
