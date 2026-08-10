part of 'codex_chat_surface.dart';

class _CodexToolMediaSummary extends StatelessWidget {
  const _CodexToolMediaSummary({required this.value});

  final _CodexToolMediaValue value;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(
        value.kind == 'image' ? AleraIcons.viewImage : AleraIcons.audio,
        size: AleraTokens.space16,
        color: AleraTokens.foregroundMuted,
      ),
      const SizedBox(width: AleraTokens.space8),
      Expanded(
        child: Text(
          '${_codexToolFieldLabel(value.kind)} - ${value.mimeType} - ${value.byteLength == null ? 'Linked media' : _codexToolByteSize(value.byteLength!)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}

class _CodexToolMediaValue {
  const _CodexToolMediaValue(this.kind, this.mimeType, this.byteLength);

  final String kind;
  final String mimeType;
  final int? byteLength;
}

String _codexToolByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

_CodexToolMediaValue? _codexToolMediaValue(Map<Object?, Object?> value) {
  final type = value['type']?.toString().toLowerCase();
  final mimeType = value['mimeType']?.toString().toLowerCase();
  final directKind = switch (type) {
    'image' || 'inputimage' => 'image',
    'audio' || 'inputaudio' => 'audio',
    _ => null,
  };
  if (directKind != null) {
    final retainedByteLength = value['byteLength'];
    if (retainedByteLength is num) {
      return _CodexToolMediaValue(
        directKind,
        mimeType ?? '$directKind/*',
        retainedByteLength.toInt(),
      );
    }
    final linkedSource = switch (type) {
      'inputimage' => value['imageUrl'],
      'inputaudio' => value['audioUrl'],
      _ => null,
    };
    if (linkedSource is String) {
      return _codexToolMediaFromSource(directKind, mimeType, linkedSource);
    }
    final embeddedData = value['data'];
    if (embeddedData is String) {
      return _CodexToolMediaValue(
        directKind,
        mimeType ?? '$directKind/*',
        _codexBase64DecodedLength(embeddedData),
      );
    }
  }
  final blob = value['blob'];
  final embeddedKind = mimeType?.startsWith('image/') == true
      ? 'image'
      : mimeType?.startsWith('audio/') == true
      ? 'audio'
      : null;
  if (embeddedKind != null && blob is String) {
    return _CodexToolMediaValue(
      embeddedKind,
      mimeType!,
      _codexBase64DecodedLength(blob),
    );
  }
  return null;
}

_CodexToolMediaValue _codexToolMediaFromSource(
  String kind,
  String? declaredMimeType,
  String source,
) {
  if (!source.startsWith('data:')) {
    return _CodexToolMediaValue(kind, declaredMimeType ?? '$kind/*', null);
  }
  final comma = source.indexOf(',');
  final metadataEnd = comma < 0 ? source.length : comma;
  final semicolon = source.indexOf(';', 5);
  final mimeEnd = semicolon >= 0 && semicolon < metadataEnd
      ? semicolon
      : metadataEnd;
  final dataMimeType = mimeEnd > 5 ? source.substring(5, mimeEnd) : null;
  return _CodexToolMediaValue(
    kind,
    declaredMimeType ?? dataMimeType ?? '$kind/*',
    comma < 0 ? 0 : _codexBase64DecodedLength(source, start: comma + 1),
  );
}

int _codexBase64DecodedLength(String source, {int start = 0}) {
  var end = source.length;
  while (end > start && _codexBase64Whitespace(source.codeUnitAt(end - 1))) {
    end -= 1;
  }
  var padding = 0;
  while (end - padding > start &&
      padding < 2 &&
      source.codeUnitAt(end - padding - 1) == 0x3d) {
    padding += 1;
  }
  final encodedLength = end - start;
  final decodedLength = encodedLength * 3 ~/ 4 - padding;
  return decodedLength < 0 ? 0 : decodedLength;
}

bool _codexBase64Whitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0a ||
    codeUnit == 0x0d;
