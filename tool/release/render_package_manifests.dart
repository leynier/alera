import 'dart:io';

/// Renders the Homebrew, Scoop, and Chocolatey package sources for a release.
///
/// The templates under `packaging/` carry `{{PLACEHOLDER}}` markers; this
/// script is the only thing that fills them, so the release workflow never
/// builds a manifest by string concatenation in YAML. Every input arrives on
/// the command line, which keeps the script runnable (and testable) outside
/// GitHub Actions, as tool/release/AGENTS.md requires.
///
/// Usage:
///   dart tool/release/render_package_manifests.dart \
///     --version 0.36.0 --tag v0.36.0 \
///     --macos-sha256 `<hex>` --windows-sha256 `<hex>` \
///     --out build/packaging
Future<void> main(List<String> arguments) async {
  final Map<String, String> options;
  try {
    options = parsePackageManifestOptions(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Usage: dart tool/release/render_package_manifests.dart '
      '--version <x.y.z> --tag <vx.y.z> --macos-sha256 <hex> '
      '--windows-sha256 <hex> --out <dir>',
    );
    exitCode = 64;
    return;
  }

  final outputRoot = Directory(options['out']!);
  final packagingRoot = Directory(options['packaging-root'] ?? 'packaging');
  final values = packageManifestValues(
    version: options['version']!,
    tag: options['tag']!,
    macosSha256: options['macos-sha256']!,
    windowsSha256: options['windows-sha256']!,
  );

  for (final entry in packageManifestOutputs.entries) {
    final template = File('${packagingRoot.path}/${entry.key}');
    if (!template.existsSync()) {
      stderr.writeln('Missing package template ${template.path}');
      exitCode = 66;
      return;
    }
    final rendered = renderPackageTemplate(
      template.readAsStringSync(),
      values,
      source: template.path,
    );
    final destination = File('${outputRoot.path}/${entry.value}');
    destination.parent.createSync(recursive: true);
    destination.writeAsStringSync(rendered);
  }

  final license = File('LICENSE');
  if (license.existsSync()) {
    File(
      '${outputRoot.path}/chocolatey/tools/LICENSE.txt',
    ).writeAsStringSync(license.readAsStringSync());
  }

  stdout.writeln('Rendered package manifests into ${outputRoot.path}');
}

/// Template path (relative to `packaging/`) mapped to its rendered path
/// (relative to the output directory).
///
/// The rendered layout is what each destination repository expects verbatim:
/// Homebrew taps read `Casks/`, Scoop buckets read `bucket/`.
const Map<String, String> packageManifestOutputs = <String, String>{
  'homebrew/alera.rb.tmpl': 'homebrew/Casks/alera.rb',
  'scoop/alera.json.tmpl': 'scoop/bucket/alera.json',
  'chocolatey/alera.nuspec.tmpl': 'chocolatey/alera.nuspec',
  'chocolatey/tools/chocolateyinstall.ps1.tmpl':
      'chocolatey/tools/chocolateyinstall.ps1',
  'chocolatey/tools/VERIFICATION.txt.tmpl': 'chocolatey/tools/VERIFICATION.txt',
  'chocolatey/tools/chocolateyuninstall.ps1':
      'chocolatey/tools/chocolateyuninstall.ps1',
};

/// The macOS asset the release workflow publishes for [version].
String macosPackageAssetName(String version) => 'alera-$version-macos.tar.gz';

/// The Windows asset the release workflow publishes for [version].
///
/// Deliberately the zip and not the tar.gz: Chocolatey and Scoop unpack a zip
/// natively, and the tar.gz stays reserved for the desktop updater.
String windowsPackageAssetName(String version) => 'alera-$version-windows.zip';

Map<String, String> packageManifestValues({
  required String version,
  required String tag,
  required String macosSha256,
  required String windowsSha256,
}) {
  return <String, String>{
    'VERSION': version,
    'TAG': tag,
    'MACOS_SHA256': macosSha256,
    'WINDOWS_SHA256': windowsSha256,
  };
}

/// Substitutes every `{{KEY}}` in [template] and fails on any leftover marker.
///
/// A silently unsubstituted placeholder would ship a manifest pointing at a
/// literal `{{VERSION}}` URL, which downloads a 404 rather than failing the cut.
String renderPackageTemplate(
  String template,
  Map<String, String> values, {
  required String source,
}) {
  var rendered = template;
  for (final entry in values.entries) {
    rendered = rendered.replaceAll('{{${entry.key}}}', entry.value);
  }
  final leftover = RegExp(r'\{\{[A-Z0-9_]+\}\}').firstMatch(rendered);
  if (leftover != null) {
    throw FormatException(
      'Unsubstituted placeholder ${leftover.group(0)} in $source',
    );
  }
  return rendered;
}

const List<String> _requiredOptions = <String>[
  'version',
  'tag',
  'macos-sha256',
  'windows-sha256',
  'out',
];

Map<String, String> parsePackageManifestOptions(List<String> arguments) {
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (!argument.startsWith('--')) {
      throw FormatException('Unexpected argument $argument');
    }
    final name = argument.substring(2);
    if (index + 1 >= arguments.length) {
      throw FormatException('Missing value for --$name');
    }
    options[name] = arguments[index + 1];
    index += 1;
  }
  for (final required in _requiredOptions) {
    final value = options[required];
    if (value == null || value.trim().isEmpty) {
      throw FormatException('Missing required option --$required');
    }
  }
  final version = options['version']!;
  if (options['tag'] != 'v$version') {
    throw FormatException(
      'Tag ${options['tag']} does not match version $version; packages are '
      'published for stable desktop cuts only.',
    );
  }
  for (final digest in <String>['macos-sha256', 'windows-sha256']) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(options[digest]!)) {
      throw FormatException('--$digest must be a lowercase hex SHA-256');
    }
  }
  return options;
}
