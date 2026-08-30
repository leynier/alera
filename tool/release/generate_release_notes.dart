import 'dart:convert';
import 'dart:io';

import 'release_plan.dart' as release_plan;

/// Generates product-scoped release notes from first-parent history.
///
/// Usage:
///   dart tool/release/generate_release_notes.dart \
///     --scope mobile|desktop --repo owner/name --tag TAG --target SHA \
///     [--previous-tag TAG] --output FILE
Future<void> main(List<String> args) async {
  final options = parseOptions(args);
  final range = options.previousTag == null
      ? options.target
      : '${options.previousTag}..${options.target}';
  final log = await _runGit(['log', '--first-parent', '--format=%H %s', range]);

  final bullets = <String>[];
  final seenPullRequests = <int>{};
  for (final entry in parseHistory(log).reversed) {
    if (isReleaseBookkeepingSubject(entry.subject)) {
      continue;
    }
    final paths = await _changedPaths(entry.sha);
    if (!pathsMatchScope(options.scope, paths)) {
      continue;
    }
    final bullet = await _resolveBullet(options.repo, entry, seenPullRequests);
    if (bullet != null) {
      bullets.add(bullet);
    }
  }

  final notes = composeReleaseNotes(
    repo: options.repo,
    tag: options.tag,
    previousTag: options.previousTag,
    bullets: bullets,
  );
  File(options.output).writeAsStringSync(notes);
  stdout.writeln('Wrote ${bullets.length} entries to ${options.output}');
}

final class const ReleaseNotesOptions({
  required final String scope,
  required final String repo,
  required final String tag,
  required final String target,
  required final String output,
  final String? previousTag,
});

ReleaseNotesOptions parseOptions(List<String> args) {
  final values = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    final flag = args[i];
    if (!flag.startsWith('--') || i + 1 >= args.length) {
      throw ArgumentError('Unexpected argument: $flag');
    }
    values[flag.substring(2)] = args[i + 1];
  }
  final scope = values['scope'];
  if (scope != 'mobile' && scope != 'desktop') {
    throw ArgumentError('--scope must be mobile or desktop');
  }
  String required(String name) {
    final value = values[name];
    if (value == null || value.isEmpty) {
      throw ArgumentError('--$name is required');
    }
    return value;
  }

  return ReleaseNotesOptions(
    scope: scope!,
    repo: required('repo'),
    tag: required('tag'),
    target: required('target'),
    output: required('output'),
    previousTag: values['previous-tag'],
  );
}

final class const HistoryEntry({
  required final String sha,
  required final String subject,
}) {
  int? get pullRequestNumber {
    final match = RegExp(r'^Merge pull request #(\d+)\b').firstMatch(subject);
    return match == null ? null : int.parse(match.group(1)!);
  }
}

List<HistoryEntry> parseHistory(String log) {
  final entries = <HistoryEntry>[];
  for (final line in const LineSplitter().convert(log)) {
    final separator = line.indexOf(' ');
    if (separator <= 0) {
      continue;
    }
    entries.add(
      HistoryEntry(
        sha: line.substring(0, separator),
        subject: line.substring(separator + 1).trim(),
      ),
    );
  }
  return entries;
}

bool isReleaseBookkeepingSubject(String subject) {
  return release_plan.isReleaseBookkeepingSubject(subject);
}

bool pathsMatchScope(String scope, Iterable<String> paths) {
  return release_plan.pathsMatchProduct(
    scope == 'mobile'
        ? release_plan.ReleaseProduct.mobile
        : release_plan.ReleaseProduct.desktop,
    paths,
  );
}

String composeReleaseNotes({
  required String repo,
  required String tag,
  required List<String> bullets,
  String? previousTag,
}) {
  final buffer = StringBuffer();
  if (bullets.isNotEmpty) {
    buffer.writeln('## What\'s Changed');
    bullets.forEach(buffer.writeln);
    buffer.writeln();
  }
  final changelogUrl = previousTag == null
      ? 'https://github.com/$repo/commits/$tag'
      : 'https://github.com/$repo/compare/$previousTag...$tag';
  buffer.writeln('**Full Changelog**: $changelogUrl');
  return buffer.toString();
}

Future<String?> _resolveBullet(
  String repo,
  HistoryEntry entry,
  Set<int> seenPullRequests,
) async {
  var prNumber = entry.pullRequestNumber;
  Map<String, dynamic>? pull;
  if (prNumber == null) {
    // A squash-merged PR lands as a plain commit; attribute it to its PR.
    final associated = jsonDecode(
      await _runGh(['api', 'repos/$repo/commits/${entry.sha}/pulls']),
    ) as List<dynamic>;
    if (associated.isNotEmpty) {
      pull = associated.first as Map<String, dynamic>;
      prNumber = pull['number'] as int;
    }
  }
  if (prNumber != null) {
    if (!seenPullRequests.add(prNumber)) {
      return null;
    }
    pull ??= jsonDecode(
      await _runGh(['api', 'repos/$repo/pulls/$prNumber']),
    ) as Map<String, dynamic>;
    final title = pull['title'] as String;
    final login = (pull['user'] as Map<String, dynamic>?)?['login'] as String?;
    final author = login == null ? '' : ' by @$login';
    return '* $title$author in https://github.com/$repo/pull/$prNumber';
  }
  final commit = jsonDecode(
    await _runGh(['api', 'repos/$repo/commits/${entry.sha}']),
  ) as Map<String, dynamic>;
  final login =
      (commit['author'] as Map<String, dynamic>?)?['login'] as String?;
  final gitName =
      ((commit['commit'] as Map<String, dynamic>?)?['author']
              as Map<String, dynamic>?)?['name']
          as String?;
  final author = login != null
      ? ' by @$login'
      : (gitName == null ? '' : ' by $gitName');
  return '* ${entry.subject}$author in '
      'https://github.com/$repo/commit/${entry.sha}';
}

Future<List<String>> _changedPaths(String sha) async {
  try {
    final diff = await _runGit(['diff', '--name-only', '$sha^1', sha]);
    return const LineSplitter().convert(diff);
  } on ProcessException {
    // A parentless root commit has no ^1; list its own tree instead.
    final show = await _runGit(['show', '--name-only', '--format=', sha]);
    return const LineSplitter().convert(show);
  }
}

Future<String> _runGit(List<String> args) => _run('git', args);

Future<String> _runGh(List<String> args) => _run('gh', args);

Future<String> _run(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return result.stdout.toString();
}
