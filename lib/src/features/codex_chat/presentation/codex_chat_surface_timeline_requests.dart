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
        ? Map<String, Object?>.from(
            widget.request.elicitationSchema['properties'] as Map,
          )
        : const <String, Object?>{};
    final required = widget.request.elicitationSchema['required'] is List
        ? (widget.request.elicitationSchema['required'] as List)
              .map((value) => value.toString())
              .toSet()
        : const <String>{};
    final isValid = properties.entries.every(
      (entry) =>
          _codexElicitationError(
            entry.value,
            _fieldFor(entry.key, entry.value).text,
            required: required.contains(entry.key),
          ) ==
          null,
    );
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
              controller: _fieldFor(entry.key, entry.value),
              keyboardType:
                  _codexElicitationType(entry.value) == 'number' ||
                      _codexElicitationType(entry.value) == 'integer'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText:
                    _codexElicitationSchemaValue(entry.value, 'title') ??
                    entry.key,
                helperText: _codexElicitationSchemaValue(
                  entry.value,
                  'description',
                ),
                hintText: _codexElicitationType(entry.value) == 'boolean'
                    ? 'true or false'
                    : null,
                errorText: _codexElicitationError(
                  entry.value,
                  _fieldFor(entry.key, entry.value).text,
                  required: required.contains(entry.key),
                ),
              ),
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
            onPressed: !isValid
                ? null
                : () => unawaited(
                    widget.onElicitation(
                      widget.request,
                      action: 'accept',
                      content: <String, Object?>{
                        for (final entry in _fields.entries)
                          if (entry.value.text.trim().isNotEmpty)
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

  TextEditingController _fieldFor(String key, Object? schema) =>
      _fields.putIfAbsent(
        key,
        () => TextEditingController(
          text: _codexElicitationSchemaValue(schema, 'default'),
        ),
      );
}

Object _codexElicitationValue(Object? schema, String value) {
  final type = _codexElicitationType(schema);
  if (type == 'number') return double.tryParse(value) ?? 0;
  if (type == 'integer') return int.tryParse(value) ?? 0;
  if (type == 'boolean') return value.toLowerCase() == 'true';
  return value;
}

String? _codexElicitationError(
  Object? schema,
  String value, {
  required bool required,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return required ? 'This field is required.' : null;
  final type = _codexElicitationType(schema);
  if (type == 'integer' && int.tryParse(trimmed) == null) {
    return 'Enter a whole number.';
  }
  if (type == 'number' && double.tryParse(trimmed) == null) {
    return 'Enter a number.';
  }
  if (type == 'boolean' && trimmed != 'true' && trimmed != 'false') {
    return 'Enter true or false.';
  }
  return null;
}

String? _codexElicitationSchemaValue(Object? schema, String key) {
  if (schema is! Map || schema[key] == null) return null;
  return schema[key].toString();
}

String? _codexElicitationType(Object? schema) =>
    _codexElicitationSchemaValue(schema, 'type');

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
