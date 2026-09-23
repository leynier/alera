import 'dart:convert';

import 'package:alera/src/features/orchestration/domain/workflow_review_snapshot.dart';
import 'package:alera/src/features/orchestration/domain/workflow_correction_selection.dart';
import 'package:alera/src/features/orchestration/domain/workflow_run_controls.dart';
import 'package:alera/src/features/orchestration/infra/workflow_decision_signer.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/foundation.dart';

class WorkflowLifecycleUpdateRequired implements Exception {
  const WorkflowLifecycleUpdateRequired();
  @override
  String toString() => 'Update the runtime to launch and review workflows.';
}

class WorkflowLifecycleRepository {
  WorkflowLifecycleRepository(
    this.client,
    this.signer, {
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final RuntimeHostClient client;
  final WorkflowDecisionSigner signer;
  final DateTime Function() now;

  Future<void> requireSupport() async {
    final capabilities = client;
    if (capabilities is! RuntimeHostCapabilityClient ||
        !await (capabilities as RuntimeHostCapabilityClient)
            .supportsRuntimeCapability(
              aleraRuntimeHostWorkflowLifecycleCapability,
            )) {
      throw const WorkflowLifecycleUpdateRequired();
    }
  }

  Future<Map<String, Object?>> request(
    String verb,
    Map<String, Object?> payload,
  ) async {
    await requireSupport();
    final result = await client.runtimeRequest(
      verb,
      payload,
      const Duration(seconds: 30),
    );
    if (result is! Map) {
      throw const FormatException('Invalid workflow lifecycle response.');
    }
    return Map<String, Object?>.from(result);
  }

  Future<Map<String, Object?>> plan(String runId) =>
      request('workflows.plan', {'runId': runId});

  Future<WorkflowCorrectionSelection> correctionSelection(
    String runId,
    int revision,
  ) async {
    final selection = await compute(
      _correctionSelection,
      await request('workflows.plan', {'runId': runId, 'revision': revision}),
    );
    selection.requireCurrent(runId, revision);
    return selection;
  }

  Future<Map<String, Object?>> createCorrection(String document) =>
      request('workflows.createCorrection', {'document': document});

  Future<WorkflowRunControls> controls(String runId, int revision) async {
    final controls = WorkflowRunControls.fromJson(
      await request('workflows.execution', {
        'runId': runId,
        'revision': revision,
      }),
    );
    if (controls.runId != runId || controls.revision != revision) {
      throw const FormatException(
        'Workflow controls do not match the selected run.',
      );
    }
    return controls;
  }

  Future<void> controlExecution(String document) async {
    await request('workflows.controlExecution', {'document': document});
  }

  Future<Map<String, Object?>> prepareRetry(Map<String, Object?> payload) =>
      request('workflows.prepareWorkspace', payload);

  Future<Map<String, Object?>> cancelProposal(String id) =>
      request('workflows.cancelProposal', {'id': id});

  Future<Map<String, Object?>> retryProposalCancellation(
    String id,
    int expectedSequence,
  ) => request('workflows.retryProposalCancellation', {
    'id': id,
    'expectedSequence': expectedSequence,
  });

  Future<Map<String, Object?>> source(String workspaceId) =>
      request('workflows.source', {'workspaceId': workspaceId});

  Future<String> proposalDocument({
    required String requestId,
    required Map<String, Object?> source,
    required Map<String, Object?> recipe,
    required String objective,
    required String coordinatorProfileId,
    required Map<String, String> roleProfiles,
    required int maxConcurrent,
    String? runId,
    int? expectedRevision,
  }) => compute(_proposalDocument, {
    'expectedSource': source['workspace'],
    'request': {
      'requestId': requestId,
      'workspaceId': (source['workspace']! as Map)['workspaceId'],
      'runId': runId,
      'expectedRevision': expectedRevision,
      'proposal': {
        'objective': objective,
        'sourceSha': source['sha'],
        'recipeSource': recipe['source'],
        'expectedRecipeDigest': recipe['digest'],
        'coordinatorProfileId': coordinatorProfileId,
        'roleProfiles': Map<String, String>.of(roleProfiles),
        'maxConcurrent': maxConcurrent,
        'tasks': <Object?>[],
      },
    },
  });

  Future<Map<String, Object?>> createProposal(String document) =>
      request('workflows.createProposal', {'document': document});

  Future<Map<String, Object?>> startCoordinator(String proposalId) =>
      request('workflows.startCoordinator', {'id': proposalId});

  Future<Map<String, Object?>> proposalStatus(String proposalId) =>
      request('workflows.proposalStatus', {'id': proposalId});

  Future<WorkflowReviewSnapshot> review(
    String runId,
    int revision,
    String scope,
  ) async {
    final snapshot = await compute(
      _reviewSnapshot,
      await request('workflows.review', {
        'runId': runId,
        'revision': revision,
        'scope': scope,
      }),
    );
    if (snapshot.runId != runId ||
        snapshot.revision != revision ||
        snapshot.scope != scope) {
      throw const FormatException(
        'Workflow review does not match the selection.',
      );
    }
    return snapshot;
  }

  Future<WorkflowPendingDecision> prepareDecision(
    WorkflowReviewSnapshot review,
    WorkflowHumanDecision decision,
    String reason,
  ) async {
    await requireSupport();
    if (!now().isBefore(review.expiresAt)) {
      throw StateError(
        'This review expired. Review the current evidence again.',
      );
    }
    if (utf8.encode(reason).length > 4096 ||
        reason.contains('\u0000') ||
        (decision != WorkflowHumanDecision.approve && reason.trim().isEmpty)) {
      throw const FormatException(
        'Provide a reason of at most 4096 UTF-8 bytes.',
      );
    }
    final statement = {
      'challenge': review.challenge,
      'decision': decision.name,
      'reason': reason,
    };
    final proof = await signer.sign(jsonEncode(statement));
    if (proof.length != 32) {
      throw StateError('Desktop workflow authorization is unavailable.');
    }
    return WorkflowPendingDecision(
      runId: review.runId,
      revision: review.revision,
      document: jsonEncode({'statement': statement, 'proof': proof.toList()}),
    );
  }

  // A lost response must replay the same signed statement, not obtain and sign
  // a new challenge for evidence the user has not seen.
  Future<Map<String, Object?>> submitDecision(
    WorkflowPendingDecision decision,
  ) => request('workflows.decide', {'document': decision.document});
}

WorkflowReviewSnapshot _reviewSnapshot(Map<String, Object?> value) =>
    WorkflowReviewSnapshot.fromJson(value);

WorkflowCorrectionSelection _correctionSelection(Map<String, Object?> value) =>
    WorkflowCorrectionSelection.fromJson(value);

String _proposalDocument(Map<String, Object?> value) {
  final request = value['request']! as Map;
  final proposal = request['proposal']! as Map;
  final objective = proposal['objective']! as String;
  final concurrent = proposal['maxConcurrent']! as int;
  if (objective.trim().isEmpty ||
      utf8.encode(objective).length > 16384 ||
      objective.contains('\u0000') ||
      concurrent < 1 ||
      concurrent > 16) {
    throw const FormatException(
      'Provide an objective of at most 16384 UTF-8 bytes and 1-16 workers.',
    );
  }
  final document = jsonEncode(value);
  if (utf8.encode(document).length > 1024 * 1024) {
    throw const FormatException(
      'The workflow proposal exceeds the byte limit.',
    );
  }
  return document;
}
