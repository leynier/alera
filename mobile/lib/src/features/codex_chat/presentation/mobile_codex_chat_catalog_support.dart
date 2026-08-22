part of 'mobile_codex_chat_screen.dart';

class _MobileCatalogIcon extends StatelessWidget {
  const _MobileCatalogIcon({required this.item});

  final _MobileCatalogItem item;

  @override
  Widget build(BuildContext context) {
    if (item.iconUrl != null) {
      return Image.network(
        item.iconUrl!,
        width: AleraTokens.space20,
        height: AleraTokens.space20,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Icon(
    item.isWorkspaceFile
        ? _mobileFileIcon(item.title)
        : Icons.extension_outlined,
    size: AleraTokens.space20,
  );
}

class _MobileCatalogItem {
  const _MobileCatalogItem({
    required this.title,
    required this.subtitle,
    required this.replacement,
    required this.kind,
    this.iconUrl,
    this.isWorkspaceFile = false,
    this.catalogInput,
  });

  final String title;
  final String subtitle;
  final String replacement;
  final String kind;
  final String? iconUrl;
  final bool isWorkspaceFile;
  final Map<String, Object?>? catalogInput;
}

class _MobileComposerToken {
  const _MobileComposerToken({
    required this.prefix,
    required this.query,
    required this.start,
    required this.end,
  });

  final String prefix;
  final String query;
  final int start;
  final int end;
}

_MobileComposerToken? _mobileComposerToken(TextEditingController controller) {
  final selection = controller.selection;
  final end = selection.isValid
      ? selection.extentOffset
      : controller.text.length;
  final before = controller.text.substring(0, end);
  final match =
      RegExp(r'(?:^|\s)([$@])([^\s]*)$').firstMatch(before) ??
      RegExp(r'^/([^\s]*)$').firstMatch(before);
  if (match == null) return null;
  final slash = match.group(0)!.startsWith('/');
  return _MobileComposerToken(
    prefix: slash ? '/' : match.group(1)!,
    query: slash ? match.group(1)! : match.group(2)!,
    start: slash
        ? 0
        : match.start + (match.group(0)!.startsWith(RegExp(r'\s')) ? 1 : 0),
    end: end,
  );
}

void _replaceComposerToken(
  TextEditingController controller,
  _MobileComposerToken token,
  String replacement,
) {
  final next = controller.text.replaceRange(
    token.start,
    token.end,
    replacement,
  );
  final offset = token.start + replacement.length;
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: offset),
  );
}

String _mobileCatalogName(Map<String, Object?> item) =>
    <Object?>[item['slug'], item['name'], item['id'], item['appId']]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .firstOrNull ??
    'Item';

String? _mobileCatalogIcon(Map<String, Object?> item) => <Object?>[
  item['iconUrl'],
  item['icon'],
  item['logoUrl'],
].whereType<String>().where((value) => value.startsWith('http')).firstOrNull;

Map<String, Object?>? _mobileSkillCatalogInput(Map<String, Object?> item) {
  final name = _mobileCatalogName(item);
  final path = item['path']?.toString();
  if (path == null || path.isEmpty) return null;
  return <String, Object?>{'type': 'skill', 'name': name, 'path': path};
}

Map<String, Object?>? _mobileAppCatalogInput(Map<String, Object?> item) {
  final name = _mobileCatalogName(item);
  final direct = item['path']?.toString();
  if (direct?.startsWith('app://') == true) {
    return <String, Object?>{'type': 'mention', 'name': name, 'path': direct};
  }
  final connector = <Object?>[
    item['connectorId'],
    item['connector_id'],
    item['appId'],
    item['id'],
  ].whereType<String>().where((value) => value.isNotEmpty).firstOrNull;
  if (connector == null) return null;
  return <String, Object?>{
    'type': 'mention',
    'name': name,
    'path': 'app://$connector',
  };
}
