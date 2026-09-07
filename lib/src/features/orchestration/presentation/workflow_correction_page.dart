import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/orchestration/application/workflow_lifecycle_providers.dart';
import 'package:alera/src/features/orchestration/domain/workflow_correction_selection.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class WorkflowCorrectionPage extends ConsumerStatefulWidget {
  const WorkflowCorrectionPage({
    super.key,
    required this.runId,
    required this.revision,
    required this.onBack,
    required this.onCreated,
  });
  final String runId;
  final int revision;
  final VoidCallback onBack;
  final ValueChanged<String> onCreated;
  @override
  ConsumerState<WorkflowCorrectionPage> createState() =>
      _WorkflowCorrectionPageState();
}

class _WorkflowCorrectionPageState
    extends ConsumerState<WorkflowCorrectionPage> {
  late final WorkflowLifecycleRepository _repository;
  final _reason = TextEditingController();
  final _requestId = const Uuid().v4();
  WorkflowCorrectionSelection? _selection;
  String? _pendingDocument;
  Object? _error;
  bool _busy = false;
  bool _reasonInitialized = false;
  bool _selectionValid = false;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(workflowLifecycleRepositoryProvider);
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _selectionValid = false;
    });
    try {
      final selection = await _repository.correctionSelection(
        widget.runId,
        widget.revision,
      );
      if (!mounted) return;
      setState(() {
        _selection = selection;
        _selectionValid = true;
        if (!_reasonInitialized) {
          _reason.text = selection.reason;
          _reasonInitialized = true;
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose() async {
    if (_busy ||
        _selection == null ||
        (_pendingDocument == null && !_selectionValid)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_pendingDocument == null) {
        if (_reason.text.trim().isEmpty ||
            utf8.encode(_reason.text).length > 4096 ||
            _reason.text.contains('\u0000')) {
          throw const FormatException(
            'Provide a correction reason of at most 4096 UTF-8 bytes.',
          );
        }
        _pendingDocument = jsonEncode({
          'requestId': _requestId,
          'runId': widget.runId,
          'revision': widget.revision,
          'planDigest': _selection!.planDigest,
          'reason': _reason.text,
        });
      }
      final draft = await _repository.createCorrection(_pendingDocument!);
      final id = draft['id']! as String;
      if (mounted) widget.onCreated(id);
      await _repository.startCoordinator(id);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    return ListView(
      padding: const EdgeInsets.all(AleraTokens.space16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : widget.onBack,
            child: const Text('Back To Run'),
          ),
        ),
        Text(
          'Prepare Correction',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AleraTokens.space12),
        const Text(
          'The coordinator proposes a new revision. Completed tasks remain in history; no worker starts until you approve the new plan.',
        ),
        if (selection != null) ...[
          const SizedBox(height: AleraTokens.space16),
          Text(
            selection.objective,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text('${selection.recipeName} / Revision ${selection.revision}'),
          const SizedBox(height: AleraTokens.space12),
          const Text('Original Source Commit'),
          SelectableText(
            selection.sourceSha,
            style: AleraTokens.monoCompactStyle,
          ),
          const SizedBox(height: AleraTokens.space12),
          const Text('Frozen Profiles'),
          for (final name in selection.profileNames) Text(name),
          const SizedBox(height: AleraTokens.space8),
          const Text(
            'The original recipe, contracts and profile configuration are retained. Later catalog edits and uncommitted source changes are not adopted.',
          ),
          const SizedBox(height: AleraTokens.space16),
          AleraTextField(
            controller: _reason,
            labelText: 'Correction Reason',
            minLines: 3,
            maxLines: 8,
            enabled: !_busy && _pendingDocument == null,
            onChanged: (_) => setState(() {}),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AleraTokens.space12),
          Text(
            _error is WorkflowLifecycleUpdateRequired
                ? 'Update Required'
                : 'Correction Needs Attention',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SelectableText(_error.toString()),
        ],
        if (_pendingDocument != null)
          const Text(
            'The request is retained for an identical retry. A saved proposal can also be reopened from Saved Proposals.',
          ),
        const SizedBox(height: AleraTokens.space16),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: [
            FilledButton(
              onPressed:
                  !_busy &&
                      selection != null &&
                      (_pendingDocument != null ||
                          (_selectionValid && _reason.text.trim().isNotEmpty))
                  ? _propose
                  : null,
              child: Text(
                _busy
                    ? 'Preparing Correction'
                    : _pendingDocument != null
                    ? 'Retry Correction'
                    : 'Propose Correction',
              ),
            ),
            if (_pendingDocument == null)
              OutlinedButton(
                onPressed: _busy ? null : _load,
                child: const Text('Refresh Revision'),
              ),
          ],
        ),
      ],
    );
  }
}
