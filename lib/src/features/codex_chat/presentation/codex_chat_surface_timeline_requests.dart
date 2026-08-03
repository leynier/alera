part of 'codex_chat_surface.dart';

class _CodexPendingCard extends StatelessWidget {
  const _CodexPendingCard({required this.request, required this.onReject});

  final CodexPendingRequest request;
  final Future<void> Function(CodexPendingRequest request) onReject;

  @override
  Widget build(BuildContext context) => _CodexRequestCard(
    title: request.requestTitle,
    body: request.method,
    actions: <Widget>[
      TextButton(
        onPressed: () => unawaited(onReject(request)),
        child: const Text('Reject'),
      ),
    ],
  );
}

class _CodexElicitationCard extends StatefulWidget {
  const _CodexElicitationCard({
    required this.request,
    required this.onElicitation,
  });

  final CodexPendingRequest request;
  final Future<void> Function(
    CodexPendingRequest request, {
    required String action,
    Map<String, Object?> content,
  })
  onElicitation;

  @override
  State<_CodexElicitationCard> createState() => _CodexElicitationCardState();
}

class _CodexElicitationCardState extends State<_CodexElicitationCard> {
  final Map<String, TextEditingController> _fields =
      <String, TextEditingController>{};

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supported = widget.request.hasSupportedElicitationForm;
    final properties = supported
        ? (widget.request.elicitationSchema['properties'] as Map)
        : const <Object?, Object?>{};
    return _CodexRequestCard(
      title: 'MCP Server Needs Input',
      bodyWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(widget.request.params['message']?.toString() ?? ''),
          if (!supported)
            const Text(
              'This elicitation form is not supported on this client.',
            ),
          for (final entry in properties.entries)
            TextField(
              controller: _fields.putIfAbsent(
                entry.key.toString(),
                TextEditingController.new,
              ),
              decoration: InputDecoration(labelText: entry.key.toString()),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () =>
              unawaited(widget.onElicitation(widget.request, action: 'cancel')),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => unawaited(
            widget.onElicitation(widget.request, action: 'decline'),
          ),
          child: const Text('Decline'),
        ),
        if (supported)
          FilledButton(
            onPressed: () => unawaited(
              widget.onElicitation(
                widget.request,
                action: 'accept',
                content: <String, Object?>{
                  for (final entry in _fields.entries)
                    entry.key: _codexElicitationValue(
                      properties[entry.key],
                      entry.value.text,
                    ),
                },
              ),
            ),
            child: const Text('Accept'),
          ),
      ],
    );
  }
}

Object _codexElicitationValue(Object? schema, String value) {
  final type = schema is Map ? schema['type']?.toString() : null;
  if (type == 'number') return double.tryParse(value) ?? 0;
  if (type == 'integer') return int.tryParse(value) ?? 0;
  if (type == 'boolean') return value.toLowerCase() == 'true';
  return value;
}

class _CodexRequestCard extends StatelessWidget {
  const _CodexRequestCard({
    required this.title,
    this.body,
    this.bodyWidget,
    required this.actions,
  });

  final String title;
  final String? body;
  final Widget? bodyWidget;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
    color: AleraTokens.surfaceElevated,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (body != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            Text(body!),
          ],
          if (bodyWidget != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            bodyWidget!,
          ],
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            Wrap(spacing: AleraTokens.space8, children: actions),
          ],
        ],
      ),
    ),
  );
}
