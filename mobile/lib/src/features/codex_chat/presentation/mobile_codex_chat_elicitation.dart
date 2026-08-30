part of 'mobile_codex_chat_screen.dart';

class const _MobileElicitationCard({
  super.key,
  required final MobileCodexPendingRequest request,
  required final MobileCodexController controller,
}) extends StatefulWidget {
  @override
  State<_MobileElicitationCard> createState() => _MobileElicitationCardState();
}

class _MobileElicitationCardState extends State<_MobileElicitationCard> {
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
          _mobileCodexElicitationError(
            entry.value,
            _fieldFor(entry.key, entry.value).text,
            required: required.contains(entry.key),
          ) ==
          null,
    );
    final message = widget.request.params['message']?.toString().trim() ?? '';
    return _MobileRequestCard(
      title: 'MCP Server Needs Input',
      bodyWidget: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (message.isNotEmpty) ...<Widget>[
            Text(message),
            const SizedBox(height: AleraTokens.space8),
          ],
          if (supported) ...<Widget>[
            for (final entry in properties.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: AleraTokens.space6),
                child: TextField(
                  controller: _fieldFor(entry.key, entry.value),
                  keyboardType:
                      _mobileCodexElicitationType(entry.value) == 'number' ||
                          _mobileCodexElicitationType(entry.value) == 'integer'
                      ? TextInputType.numberWithOptions(
                          signed: true,
                          decimal:
                              _mobileCodexElicitationType(entry.value) ==
                              'number',
                        )
                      : TextInputType.text,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText:
                        _mobileCodexElicitationSchemaValue(
                          entry.value,
                          'title',
                        ) ??
                        entry.key,
                    helperText: _mobileCodexElicitationSchemaValue(
                      entry.value,
                      'description',
                    ),
                    hintText:
                        _mobileCodexElicitationType(entry.value) == 'boolean'
                        ? 'true or false'
                        : null,
                    errorText: _mobileCodexElicitationError(
                      entry.value,
                      _fieldFor(entry.key, entry.value).text,
                      required: required.contains(entry.key),
                    ),
                  ),
                ),
              ),
          ] else
            const Text('This MCP input form is not supported on mobile.'),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => unawaited(
            widget.controller.respondElicitation(
              widget.request,
              action: 'cancel',
            ),
          ),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => unawaited(
            widget.controller.respondElicitation(
              widget.request,
              action: 'decline',
            ),
          ),
          child: const Text('Decline'),
        ),
        if (supported)
          FilledButton(
            onPressed: !isValid
                ? null
                : () => unawaited(
                    widget.controller.respondElicitation(
                      widget.request,
                      action: 'accept',
                      content: <String, Object?>{
                        for (final entry in _fields.entries)
                          if (entry.value.text.trim().isNotEmpty)
                            entry.key: _mobileCodexElicitationValue(
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
          text: _mobileCodexElicitationSchemaValue(schema, 'default'),
        ),
      );
}

Object _mobileCodexElicitationValue(Object? schema, String value) {
  final type = _mobileCodexElicitationType(schema);
  final normalized = value.trim();
  if (type == 'number') return double.parse(normalized);
  if (type == 'integer') return int.parse(normalized);
  if (type == 'boolean') return normalized.toLowerCase() == 'true';
  return value;
}

String? _mobileCodexElicitationError(
  Object? schema,
  String value, {
  required bool required,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return required ? 'This field is required.' : null;
  final type = _mobileCodexElicitationType(schema);
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

String? _mobileCodexElicitationSchemaValue(Object? schema, String key) {
  if (schema is! Map || schema[key] == null) return null;
  return schema[key].toString();
}

String? _mobileCodexElicitationType(Object? schema) =>
    _mobileCodexElicitationSchemaValue(schema, 'type');
