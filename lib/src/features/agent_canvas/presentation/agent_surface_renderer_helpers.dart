part of 'agent_surface_renderer.dart';

class const _SurfaceCard({
  required final Widget child,
  final bool emphasized = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: emphasized ? AleraTokens.surfaceElevated : AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(
          color: emphasized ? AleraTokens.info : AleraTokens.borderSubtle,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: child,
      ),
    );
  }
}

class const _StatusPill(final String value) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.accentSubtle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space4,
        ),
        child: Text(value),
      ),
    );
  }
}

class const _KeyValueRows({
  required final String title,
  required final Map<String, Object?> values,
  required final List<String> keys,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Text(title),
        const SizedBox(height: AleraTokens.space6),
        for (final key in keys)
          if (values[key] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space4),
              child: Text('${_label(key)}: ${_display(values[key])}'),
            ),
      ],
    );
  }
}

Map<String, Object?>? _object(Object? value) {
  return value is Map ? Map<String, Object?>.from(value) : null;
}

String _string(Map<String, Object?> props, String key, {String fallback = ''}) {
  final value = props[key];
  return value is String && value.trim().isNotEmpty ? value : fallback;
}

int _number(Map<String, Object?> props, String key) {
  return (props[key] as num?)?.toInt() ?? 0;
}

String _display(Object? value) {
  if (value is Map || value is List) {
    return value.toString();
  }
  return value?.toString() ?? '';
}

String _label(String value) {
  return value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1)}';
}

Map<String, Object?> _actionFrom(Map value) {
  final action = value['action'];
  if (action is Map) {
    return Map<String, Object?>.from(action);
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String && entry.key != 'label')
        entry.key as String: entry.value,
  };
}
