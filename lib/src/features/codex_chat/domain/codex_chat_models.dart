import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'codex_timeline.dart';

part 'codex_chat_state.dart';
part 'codex_chat_models_helpers.dart';
part 'codex_thread_models.dart';
part 'codex_thread_goal.dart';
part 'codex_chat_snapshot_models.dart';
part 'codex_chat_snapshot_delta.dart';
part 'codex_timeline_event.dart';

@immutable
class const CodexModelOption({
  required final String id,
  required final String label,
  final bool isDefault = false,
  final int? contextWindowTokens,
  final bool supportsFastMode = false,
  final List<String> reasoningEfforts = const <String>[],
  final String? defaultReasoningEffort,
  final Map<String, Object?> metadata = const <String, Object?>{},
}) {
  factory fromJson(Map<String, Object?> json) {
    final id = _firstString(<Object?>[json['id'], json['model'], json['name']]);
    final label = _firstString(<Object?>[
      json['displayName'],
      json['label'],
      json['name'],
      id,
    ]);
    final reasoning =
        json['reasoningEfforts'] ??
        json['supportedReasoningEfforts'] ??
        (json['reasoning'] is Map
            ? (json['reasoning'] as Map)['efforts']
            : null);
    return CodexModelOption(
      id: id.isEmpty ? 'unknown' : id,
      label: codexModelDisplayLabel(label.isEmpty ? id : label),
      isDefault: json['isDefault'] == true || json['default'] == true,
      contextWindowTokens: _int(
        json['contextWindowTokens'] ?? json['contextWindow'],
      ),
      defaultReasoningEffort: _string(json['defaultReasoningEffort']),
      supportsFastMode:
          json['supportsFastMode'] == true ||
          _containsFast(json['serviceTier']) ||
          _containsFast(json['additionalSpeedTiers']) ||
          _containsFast(json['serviceTiers']) ||
          _containsFast(json['supportedServiceTiers']) ||
          _containsFast(json['serviceTierOptions']),
      reasoningEfforts: _reasoningEfforts(reasoning),
      metadata: json,
    );
  }
}

@immutable
class const CodexInputAttachment({
  final String? id,
  required final String path,
  required final bool isImage,
  final String? mimeType,
  final String? displayName,
  final int? sizeBytes,
  final String? detail,
  final bool isDirectory = false,
  final CodexInputAttachmentOrigin origin =
      CodexInputAttachmentOrigin.attachment,
  final String? tokenText,
  final int? tokenStart,
  final String? annotationContext,
  final String? annotationUrl,
  final String? annotationTitle,
  final int? annotationCount,
}) {
  bool get isBrowserAnnotation => annotationContext != null;

  CodexInputAttachment copyWith({int? sizeBytes, bool? isDirectory}) =>
      CodexInputAttachment(
        id: id,
        path: path,
        isImage: isImage,
        mimeType: mimeType,
        displayName: displayName,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        detail: detail,
        isDirectory: isDirectory ?? this.isDirectory,
        origin: origin,
        tokenText: tokenText,
        tokenStart: tokenStart,
        annotationContext: annotationContext,
        annotationUrl: annotationUrl,
        annotationTitle: annotationTitle,
        annotationCount: annotationCount,
      );
}

enum CodexInputAttachmentOrigin { attachment, mention }

enum CodexDraftItemKind { skill, app, mention }

@immutable
class const CodexDraftItem({
  required final String id,
  required final CodexDraftItemKind kind,
  required final String name,
  required final String path,
  final String? tokenText,
  final int? tokenStart,
  final String? iconUrl,
}) {
  CodexDraftItem copyWith({int? tokenStart}) => CodexDraftItem(
    id: id,
    kind: kind,
    name: name,
    path: path,
    tokenText: tokenText,
    tokenStart: tokenStart ?? this.tokenStart,
    iconUrl: iconUrl,
  );
}

@immutable
class const CodexQueuedMessage({
  required final String text,
  final List<CodexInputAttachment> attachments = const <CodexInputAttachment>[],
  final List<CodexDraftItem> draftItems = const <CodexDraftItem>[],
  final String? id,
});

@immutable
class const CodexQuestionOption({
  required final String label,
  final String? description,
}) {
  factory fromJson(Object? value) {
    final json = _map(value);
    return CodexQuestionOption(
      label: _firstString(<Object?>[json['label'], json['value'], value]),
      description: _string(json['description']),
    );
  }
}

@immutable
class const CodexQuestion({
  required final String id,
  required final String question,
  final String? header,
  final List<CodexQuestionOption> options = const <CodexQuestionOption>[],
  final bool isOther = false,
  final bool isSecret = false,
  final bool isMultiSelect = false,
}) {
  factory fromJson(Object? value, {int index = 0}) {
    final json = _map(value);
    return CodexQuestion(
      id: _firstString(<Object?>[json['id'], json['key'], 'question-$index']),
      question: _firstString(<Object?>[
        json['question'],
        json['prompt'],
        json['text'],
        'Codex asked a question.',
      ]),
      header: _string(json['header']),
      options: <CodexQuestionOption>[
        if (json['options'] is List)
          for (final option in json['options'] as List)
            CodexQuestionOption.fromJson(option),
      ],
      isOther: json['isOther'] == true,
      isSecret: json['isSecret'] == true,
      isMultiSelect:
          json['isMultiSelect'] == true || json['multiSelect'] == true,
    );
  }
}

@immutable
class const CodexPendingRequest({
  required final Object id,
  required final String method,
  required final Map<String, Object?> params,
}) {
  factory fromJson(Object? value) {
    final json = _map(value);
    return CodexPendingRequest(
      id: json['id'] ?? '',
      method: _string(json['method']) ?? 'request',
      params: _map(json['params']),
    );
  }

  bool get isApproval {
    final methodName = method.toLowerCase();
    return methodName.contains('approval') ||
        methodName.contains('permission') ||
        methodName.contains('requestcommand') ||
        methodName.contains('requestfile');
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
    final methodName = method.toLowerCase();
    return methodName.contains('question') ||
        methodName.contains('userinput') ||
        methodName.contains('request_user_input') ||
        params['questions'] is List;
  }

  List<CodexQuestion> get questions {
    final values = params['questions'];
    if (values is List && values.isNotEmpty) {
      return <CodexQuestion>[
        for (var index = 0; index < values.length; index++)
          CodexQuestion.fromJson(values[index], index: index),
      ];
    }
    return <CodexQuestion>[CodexQuestion.fromJson(params)];
  }

  String get requestTitle => isApproval
      ? 'Codex Needs Approval'
      : isElicitation
      ? 'MCP Server Needs Input'
      : isQuestion
      ? 'Codex Needs Your Input'
      : 'Codex Request';

  String get approvalDescription => _firstString(<Object?>[
    params['reason'],
    params['command'],
    params['path'],
    params['filePath'],
    'Codex is requesting permission to continue.',
  ]);

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
      'decline' => 'denied',
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
    if (value is! Map) return decision;
    final amendment = value['network_policy_amendment'];
    if (amendment is! Map) return decision;
    return <String, Object?>{
      'network_policy_amendment': <String, Object?>{
        'network_policy_amendment': Map<String, Object?>.from(amendment),
      },
    };
  }
}
