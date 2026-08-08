import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart tool/generate_gpui_material_icon_manifest.dart '
      '<vscode_material_icon_theme package> <output>',
    );
    exitCode = 64;
    return;
  }

  final package = Directory(arguments.first);
  final rules = File('${package.path}/lib/rules.g.dart').readAsStringSync();
  final iconCatalog = _parseIconCatalog(
    File('${package.path}/lib/icon.g.dart').readAsStringSync(),
  );
  final languages = File(
    '${package.path}/lib/language_map.dart',
  ).readAsStringSync();
  final languageIcons = _parseLanguageIcons(rules, iconCatalog);
  final resolvedFileExtensions = _parseAssetMap(
    rules,
    'fileExtensions',
    iconCatalog,
  );
  _mergeLanguageFallbacks(
    resolvedFileExtensions,
    _parseLanguageMap(languages, 'extensionToLanguageId'),
    languageIcons,
    stripLeadingDot: true,
  );
  final resolvedFileNames = _parseAssetMap(rules, 'fileNames', iconCatalog);
  _mergeLanguageFallbacks(
    resolvedFileNames,
    _parseLanguageMap(languages, 'filenameToLanguageId'),
    languageIcons,
  );

  final manifest = <String, Object>{
    'file': _parseAssetConstant(rules, 'file', iconCatalog),
    'folder': _parseAssetConstant(rules, 'folder', iconCatalog),
    'folderExpanded': _parseAssetConstant(rules, 'folderExpanded', iconCatalog),
    'fileExtensions': _sorted(resolvedFileExtensions),
    'fileNames': _sorted(resolvedFileNames),
    'folderNames': _sorted(_parseAssetMap(rules, 'folderNames', iconCatalog)),
    'folderNamesExpanded': _sorted(
      _parseAssetMap(rules, 'folderNamesExpanded', iconCatalog),
    ),
  };
  File(arguments[1]).writeAsStringSync(jsonEncode(manifest));
}

String _parseAssetConstant(
  String source,
  String name,
  Map<String, String> iconCatalog,
) {
  final match = RegExp(
    'const ${RegExp.escape(name)} = MaterialIcons\\.([\\w-]+);',
  ).firstMatch(source);
  if (match == null) {
    throw FormatException('Missing icon constant $name');
  }
  return _resolveIcon(match.group(1)!, iconCatalog);
}

Map<String, String> _parseAssetMap(
  String source,
  String name,
  Map<String, String> iconCatalog,
) {
  final body = _mapBody(source, 'const $name = {');
  final entries = <String, String>{};
  final pattern = RegExp(
    r'''^\s*["'](.+?)["']:\s*MaterialIcons\.([\w-]+),\s*$''',
    multiLine: true,
  );
  for (final match in pattern.allMatches(body)) {
    entries[match.group(1)!.toLowerCase()] = _resolveIcon(
      match.group(2)!,
      iconCatalog,
    );
  }
  return entries;
}

Map<String, String> _parseLanguageIcons(
  String source,
  Map<String, String> iconCatalog,
) {
  final body = _mapBody(source, 'const languageIds = {');
  final entries = <String, String>{};
  final pattern = RegExp(
    r'^\s*VSCodeLanguageId\.([\w]+):\s*MaterialIcons\.([\w-]+),\s*$',
    multiLine: true,
  );
  for (final match in pattern.allMatches(body)) {
    entries[match.group(1)!] = _resolveIcon(match.group(2)!, iconCatalog);
  }
  return entries;
}

Map<String, String> _parseIconCatalog(String source) {
  final entries = <String, String>{};
  final pattern = RegExp(
    r'''static const ([\w]+) = AssetBytesLoader\("assets/icons/(.+?)\.vec"''',
  );
  for (final match in pattern.allMatches(source)) {
    entries[match.group(1)!] = match.group(2)!;
  }
  return entries;
}

String _resolveIcon(String symbol, Map<String, String> iconCatalog) {
  final filename = iconCatalog[symbol];
  if (filename == null) {
    throw FormatException('Missing icon catalog entry $symbol');
  }
  return filename;
}

Map<String, String> _parseLanguageMap(String source, String name) {
  final body = _mapBody(
    source,
    'const Map<String, VSCodeLanguageId> $name = {',
  );
  final entries = <String, String>{};
  final pattern = RegExp(
    r'''^\s*["'](.+?)["']:\s*VSCodeLanguageId\.([\w]+),\s*$''',
    multiLine: true,
  );
  for (final match in pattern.allMatches(body)) {
    entries[match.group(1)!.toLowerCase()] = match.group(2)!;
  }
  return entries;
}

String _mapBody(String source, String marker) {
  final start = source.indexOf(marker);
  if (start < 0) {
    throw FormatException('Missing map marker $marker');
  }
  final bodyStart = start + marker.length;
  final end = source.indexOf('\n};', bodyStart);
  if (end < 0) {
    throw FormatException('Unterminated map $marker');
  }
  return source.substring(bodyStart, end);
}

void _mergeLanguageFallbacks(
  Map<String, String> destination,
  Map<String, String> languageByName,
  Map<String, String> iconByLanguage, {
  bool stripLeadingDot = false,
}) {
  for (final entry in languageByName.entries) {
    final icon = iconByLanguage[entry.value];
    if (icon == null) {
      continue;
    }
    final key = stripLeadingDot
        ? entry.key.replaceFirst(RegExp(r'^\.'), '')
        : entry.key;
    destination.putIfAbsent(key, () => icon);
  }
}

Map<String, String> _sorted(Map<String, String> source) {
  final entries = source.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return Map.fromEntries(entries);
}
