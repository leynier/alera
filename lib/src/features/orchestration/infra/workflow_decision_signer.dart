import 'dart:typed_data';

import 'package:alera/src/rust/api/workflow_approval.dart' as native;

abstract interface class WorkflowDecisionSigner {
  Future<Uint8List> sign(String statementJson);
}

/// This boundary is local desktop only. Never send the credential itself to
/// Dart, a runtime request, a terminal environment or a portable recipe.
final class NativeWorkflowDecisionSigner implements WorkflowDecisionSigner {
  const NativeWorkflowDecisionSigner(this.runtimeDirectory);

  final String runtimeDirectory;

  @override
  Future<Uint8List> sign(String statementJson) => native.signWorkflowDecision(
    runtimeDir: runtimeDirectory,
    statementJson: statementJson,
  );
}
