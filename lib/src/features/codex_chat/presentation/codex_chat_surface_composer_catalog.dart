part of 'codex_chat_surface.dart';

class const _CodexCatalogAppIcon({final String? url}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final value = url;
    final fallback = Icon(
      AleraIcons.public,
      size: AleraTokens.iconMd,
      color: AleraTokens.foregroundMuted,
    );
    if (value == null) return fallback;
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return fallback;
    }
    return SizedBox.square(
      dimension: AleraTokens.iconMd,
      child: uri.path.toLowerCase().endsWith('.svg')
          ? SvgPicture.network(
              value,
              excludeFromSemantics: true,
              placeholderBuilder: (_) => fallback,
              errorBuilder: (_, _, _) => fallback,
            )
          : Image.network(
              value,
              fit: .contain,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class const _CodexCatalogPickerDialog({
  required final String title,
  required final List<Map<String, Object?>> items,
  required final String searchHint,
}) extends StatefulWidget {
  @override
  State<_CodexCatalogPickerDialog> createState() =>
      _CodexCatalogPickerDialogState();
}

class _CodexCatalogPickerDialogState extends State<_CodexCatalogPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final items = widget.items
        .where((item) {
          if (_query.isEmpty) return true;
          final text = item.values.join(' ').toLowerCase();
          return text.contains(_query.toLowerCase());
        })
        .toList(growable: false);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AleraTokens.dialogCompactWidth,
          maxWidth: AleraTokens.dialogWideWidth,
          maxHeight: AleraTokens.dialogMaxHeight,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space16,
                AleraTokens.space16,
                AleraTokens.space8,
                AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  AleraIconButton(
                    tooltip: 'Close',
                    icon: AleraIcons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
              ),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(hintText: widget.searchHint),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: AleraTokens.space8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: ListTile(
                      dense: true,
                      leading:
                          item['path']?.toString().trim().isNotEmpty == true
                          ? const Icon(
                              AleraIcons.package,
                              size: AleraTokens.iconMd,
                            )
                          : _CodexCatalogAppIcon(url: _catalogIconUrl(item)),
                      title: Text(_catalogName(item)),
                      subtitle: Text(_catalogDescription(item)),
                      trailing: Text(_catalogScope(item)),
                      onTap: () => Navigator.of(context).pop(item),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _catalogName(Map<String, Object?> item) {
  final interface = item['interface'];
  if (interface is Map) {
    final displayName = interface['displayName']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
  }
  for (final key in <String>['slug', 'name', 'id', 'appId']) {
    final value = item[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return 'Unknown';
}

String _catalogDescription(Map<String, Object?> item) {
  final interface = item['interface'];
  if (interface is Map) {
    final description = interface['shortDescription']?.toString().trim();
    if (description != null && description.isNotEmpty) return description;
  }
  for (final key in <String>['shortDescription', 'description', 'name']) {
    final value = item[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return '';
}

String _catalogScope(Map<String, Object?> item) =>
    item['scope']?.toString().trim() ?? '';

String? _catalogIconUrl(Map<String, Object?> item) {
  final interface = item['interface'];
  final sources = <Map<String, Object?>>[
    item,
    if (interface is Map)
      interface.map((key, value) => MapEntry(key.toString(), value)),
  ];
  for (final source in sources) {
    for (final key in <String>['logoUrlDark', 'composerIconUrl', 'logoUrl']) {
      final url = _validCatalogIconUrl(source[key]);
      if (url != null) return url;
    }
    for (final key in <String>['iconDarkAssets', 'iconAssets']) {
      final assets = source[key];
      if (assets is! Map) continue;
      final entries = assets.entries.toList(growable: false)
        ..sort(
          (left, right) => left.key.toString().compareTo(right.key.toString()),
        );
      for (final entry in entries.reversed) {
        final url = _validCatalogIconUrl(entry.value);
        if (url != null) return url;
      }
    }
  }
  return null;
}

String? _validCatalogIconUrl(Object? value) {
  final url = value?.toString().trim();
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
      ? url
      : null;
}
