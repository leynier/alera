import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_canvas/domain/agent_canvas.dart';
import 'package:flutter/material.dart';

part 'agent_surface_renderer_helpers.dart';

typedef AgentCanvasActionCallback = Future<void> Function(
  Map<String, Object?> action,
);

abstract interface class AgentSurfaceRenderer {
  Widget build(
    BuildContext context, {
    required AgentCanvas canvas,
    required AgentCanvasActionCallback onAction,
  });
}

/// The renderer pins the accepted document contract to one version. Agent
/// payloads are data only: component names and action kinds are allowlisted by
/// this renderer and validated again by the runtime host.
final class const PinnedGenUiAgentSurfaceRenderer()
    implements AgentSurfaceRenderer {
  static const int version = 1;

  @override
  Widget build(
    BuildContext context, {
    required AgentCanvas canvas,
    required AgentCanvasActionCallback onAction,
  }) {
    return _AgentSurfaceDocument(canvas: canvas, onAction: onAction);
  }
}

class const _AgentSurfaceDocument({
  required final AgentCanvas canvas,
  required final AgentCanvasActionCallback onAction,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final components = canvas.document['components'];
    final widgets = <Widget>[];
    if (components is List) {
      for (final value in components) {
        if (value is! Map) {
          continue;
        }
        final item = Map<String, Object?>.from(value);
        final type = item['type'] ?? item['component'];
        final props = _object(item['props']) ?? item;
        final widget = _component(
          type is String ? type : '',
          props,
          canvas,
          onAction,
        );
        if (widget != null) {
          widgets.add(widget);
          widgets.add(const SizedBox(height: AleraTokens.space8));
        }
      }
    }
    if (widgets.isEmpty) {
      widgets.add(
        const AgentNotice(
          tone: 'info',
          text: 'This Agent Canvas has no visible components yet.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AleraTokens.space12),
      children: widgets,
    );
  }

  Widget? _component(
    String type,
    Map<String, Object?> props,
    AgentCanvas canvas,
    AgentCanvasActionCallback onAction,
  ) {
    return switch (type) {
      'AgentRunHeader' => AgentRunHeader(props: props),
      'TaskProgress' => TaskProgress(props: props),
      'DecisionRequest' => DecisionRequest(
        props: props,
        decisionId: _decisionId(props, canvas),
        onAction: onAction,
      ),
      'ChangeSummary' => ChangeSummary(props: props),
      'FileReferenceList' => FileReferenceList(
        props: props,
        onAction: onAction,
      ),
      'ValidationResults' => ValidationResults(props: props),
      'RiskSummary' => RiskSummary(props: props),
      'ArtifactCard' => ArtifactCard(props: props, onAction: onAction),
      'Notice' => AgentNotice(
        tone: _string(props, 'tone', fallback: 'info'),
        text: _string(props, 'text'),
      ),
      'ActionGroup' => ActionGroup(props: props, onAction: onAction),
      _ => null,
    };
  }
}

String? _decisionId(Map<String, Object?> props, AgentCanvas canvas) {
  final explicit = _string(props, 'id');
  if (explicit.isNotEmpty) {
    return explicit;
  }
  final question = _string(props, 'question');
  for (final decision in canvas.decisions) {
    if (decision.isPending &&
        decision.revision == canvas.revision &&
        (question.isEmpty || decision.question == question)) {
      return decision.id;
    }
  }
  return null;
}

class const AgentRunHeader({
  super.key,
  required final Map<String, Object?> props,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Row(
        children: <Widget>[
          const Icon(AleraIcons.agent, size: 18, color: AleraTokens.info),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              _string(props, 'title', fallback: 'Agent Run'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          _StatusPill(_string(props, 'status', fallback: 'live')),
        ],
      ),
    );
  }
}

class const TaskProgress({super.key, required final Map<String, Object?> props})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final completed = _number(props, 'completed');
    final total = _number(props, 'total').clamp(1, 100000);
    final progress = (completed / total).clamp(0.0, 1.0);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Text(_string(props, 'label', fallback: 'Task Progress')),
          const SizedBox(height: AleraTokens.space8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: AleraTokens.space6),
          Text(
            '$completed of $total complete',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class const DecisionRequest({
  super.key,
  required final Map<String, Object?> props,
  required final AgentCanvasActionCallback onAction,
  final String? decisionId,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final options = props['options'];
    final optionValues = options is List ? options : const <Object?>[];
    final id = decisionId ?? _string(props, 'id');
    return _SurfaceCard(
      emphasized: true,
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Text(
            'Decision Request',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AleraTokens.space6),
          Text(_string(props, 'question', fallback: 'Choose an option.')),
          if (optionValues.isNotEmpty) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            for (final option in optionValues)
              Padding(
                padding: const EdgeInsets.only(bottom: AleraTokens.space4),
                child: OutlinedButton(
                  onPressed: () => onAction(<String, Object?>{
                    'kind': 'resolveDecision',
                    'decisionId': id,
                    'resolution': option,
                    'confirmed': true,
                  }),
                  child: Text(_display(option)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class const ChangeSummary({
  super.key,
  required final Map<String, Object?> props,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: _KeyValueRows(
        title: 'Change Summary',
        values: props,
        keys: const <String>['added', 'modified', 'deleted', 'summary'],
      ),
    );
  }
}

class const FileReferenceList({
  super.key,
  required final Map<String, Object?> props,
  required final AgentCanvasActionCallback onAction,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final files = props['files'];
    final values = files is List ? files : const <Object?>[];
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          const Text('Files'),
          const SizedBox(height: AleraTokens.space6),
          for (final file in values)
            Material(
              type: .transparency,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(AleraIcons.file, size: 16),
                title: Text(_display(file)),
                onTap: file is String
                    ? () => onAction(<String, Object?>{
                        'kind': 'openFile',
                        'relativePath': file,
                      })
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class const ValidationResults({
  super.key,
  required final Map<String, Object?> props,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final results = props['results'];
    final values = results is List ? results : const <Object?>[];
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          const Text('Validation Results'),
          const SizedBox(height: AleraTokens.space6),
          for (final result in values)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space4),
              child: Text(_display(result)),
            ),
        ],
      ),
    );
  }
}

class const RiskSummary({super.key, required final Map<String, Object?> props})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final level = _string(props, 'level', fallback: 'unknown');
    return _SurfaceCard(
      child: Row(
        children: <Widget>[
          const Icon(AleraIcons.secure, size: 17, color: AleraTokens.warning),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(_string(props, 'summary', fallback: 'Risk Summary')),
          ),
          _StatusPill(level),
        ],
      ),
    );
  }
}

class const ArtifactCard({
  super.key,
  required final Map<String, Object?> props,
  required final AgentCanvasActionCallback onAction,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final artifactId = _string(props, 'artifactId');
    return _SurfaceCard(
      child: Row(
        children: <Widget>[
          const Icon(AleraIcons.file, size: 18),
          const SizedBox(width: AleraTokens.space8),
          Expanded(child: Text(_string(props, 'title', fallback: 'Artifact'))),
          if (artifactId.isNotEmpty)
            TextButton(
              onPressed: () => onAction(<String, Object?>{
                'kind': 'openArtifact',
                'artifactId': artifactId,
              }),
              child: const Text('Open'),
            ),
        ],
      ),
    );
  }
}

class const AgentNotice({
  super.key,
  required final String tone,
  required final String text,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      'error' => AleraTokens.error,
      'warning' => AleraTokens.warning,
      'success' => AleraTokens.success,
      _ => AleraTokens.info,
    };
    return _SurfaceCard(
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          Icon(AleraIcons.info, size: 17, color: color),
          const SizedBox(width: AleraTokens.space8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class const ActionGroup({
  super.key,
  required final Map<String, Object?> props,
  required final AgentCanvasActionCallback onAction,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = props['actions'];
    final values = actions is List ? actions : const <Object?>[];
    return _SurfaceCard(
      child: Wrap(
        spacing: AleraTokens.space6,
        runSpacing: AleraTokens.space6,
        children: <Widget>[
          for (final value in values)
            if (value is Map)
              OutlinedButton(
                onPressed: () => onAction(_actionFrom(value)),
                child: Text(
                  _string(
                    Map<String, Object?>.from(value),
                    'label',
                    fallback: 'Action',
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
