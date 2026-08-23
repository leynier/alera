import 'dart:convert';
import 'dart:io';

Map<String, Object> desiredMainRuleset({
  required int mergifyAppId,
  required int githubActionsAppId,
}) => {
  'name': 'protect main',
  'target': 'branch',
  'enforcement': 'active',
  'bypass_actors': [
    {
      'actor_id': mergifyAppId,
      'actor_type': 'Integration',
      'bypass_mode': 'always',
    },
  ],
  'conditions': {
    'ref_name': {
      'include': ['~DEFAULT_BRANCH'],
      'exclude': <String>[],
    },
  },
  'rules': [
    {'type': 'deletion'},
    {'type': 'non_fast_forward'},
    {
      'type': 'pull_request',
      'parameters': {
        'allowed_merge_methods': ['squash'],
        'dismiss_stale_reviews_on_push': false,
        'require_code_owner_review': false,
        'require_last_push_approval': false,
        'required_approving_review_count': 0,
        'required_review_thread_resolution': true,
      },
    },
    {
      'type': 'required_status_checks',
      'parameters': {
        'do_not_enforce_on_create': false,
        'required_status_checks': [
          {'context': 'pr-ready', 'integration_id': githubActionsAppId},
          {'context': 'queue-ready', 'integration_id': githubActionsAppId},
        ],
        'strict_required_status_checks_policy': false,
      },
    },
  ],
};

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final repository = options.repository;
  final repositoryInfo = _jsonObject(
    jsonDecode(await _ghApi('repos/$repository')),
    'repository',
  );
  if (repositoryInfo['default_branch'] != 'main') {
    throw StateError('$repository does not use main as its default branch.');
  }

  await _verifyWriterOnMain(repository);
  await _verifyDryRun(repository, options.dryRunRunId);

  final mergifyAppId = _appId(await _ghApi('apps/mergify'), 'mergify');
  final githubActionsAppId = _appId(
    await _ghApi('apps/github-actions'),
    'github-actions',
  );
  final desired = desiredMainRuleset(
    mergifyAppId: mergifyAppId,
    githubActionsAppId: githubActionsAppId,
  );
  final existing = _jsonList(
    jsonDecode(await _ghApi('repos/$repository/rulesets')),
    'rulesets',
  );

  if (existing.isNotEmpty) {
    if (existing.length != 1 || existing.single['name'] != desired['name']) {
      throw StateError(
        'Repository rulesets changed since issue #489 was inspected. '
        'Review the live rulesets before applying anything.',
      );
    }
    final id = existing.single['id'];
    final current = _jsonObject(
      jsonDecode(await _ghApi('repos/$repository/rulesets/$id')),
      'ruleset',
    );
    if (!_sameManagedRuleset(current, desired)) {
      throw StateError(
        'The existing protect main ruleset differs from the desired payload. '
        'This script will not overwrite it.',
      );
    }
    stdout.writeln('The active protect main ruleset already matches.');
    await _verifyEffectiveRules(repository);
    return;
  }

  if (!options.apply) {
    stdout.writeln('Preflight passed. No ruleset was changed.');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(desired));
    stdout.writeln(
      'Re-run with --apply only after reviewing this payload and the dry-run.',
    );
    return;
  }

  final created = _jsonObject(
    jsonDecode(
      await _ghApi('repos/$repository/rulesets', method: 'POST', body: desired),
    ),
    'created ruleset',
  );
  if (!_sameManagedRuleset(created, desired)) {
    throw StateError(
      'GitHub created a ruleset that does not match the payload.',
    );
  }
  await _verifyEffectiveRules(repository);
  final links = created['_links'];
  final html = links is Map<String, dynamic> ? links['html'] : null;
  final url = html is Map<String, dynamic> ? html['href'] : null;
  stdout.writeln('Activated protect main${url is String ? ': $url' : '.'}');
}

Future<void> _verifyWriterOnMain(String repository) async {
  final response = _jsonObject(
    jsonDecode(
      await _ghApi(
        'repos/$repository/contents/.github/workflows/release-cut.yml?ref=main',
      ),
    ),
    'release workflow',
  );
  final encoded = response['content'];
  if (encoded is! String) {
    throw const FormatException('Workflow has no content.');
  }
  final workflow = utf8.decode(base64.decode(encoded.replaceAll('\n', '')));
  const requiredMarkers = [
    'prepare_version_pr:',
    'prepared_release.dart inspect',
    'Publish merged version PR',
    'git push --atomic origin "\${tag_refspecs[@]}"',
  ];
  for (final marker in requiredMarkers) {
    if (!workflow.contains(marker)) {
      throw StateError('origin/main is missing release writer marker: $marker');
    }
  }
  if (workflow.contains('HEAD:refs/heads/main') ||
      workflow.contains('--force-with-lease origin HEAD~1:refs/heads/main')) {
    throw StateError('origin/main still lets release-cut.yml write main.');
  }
}

Future<void> _verifyDryRun(String repository, int runId) async {
  final run = _jsonObject(
    jsonDecode(await _ghApi('repos/$repository/actions/runs/$runId')),
    'workflow run',
  );
  final title = run['display_title'];
  if (run['event'] != 'workflow_dispatch' ||
      run['conclusion'] != 'success' ||
      run['head_branch'] != 'main' ||
      title is! String ||
      !title.contains('dry_run=true')) {
    throw StateError(
      'Run $runId is not a successful Cut Release dry run on main.',
    );
  }
}

Future<void> _verifyEffectiveRules(String repository) async {
  final rules = _jsonList(
    jsonDecode(await _ghApi('repos/$repository/rules/branches/main')),
    'effective rules',
  );
  final types = rules.map((rule) => rule['type']).toSet();
  const expected = {
    'deletion',
    'non_fast_forward',
    'pull_request',
    'required_status_checks',
  };
  if (!types.containsAll(expected)) {
    throw StateError('The effective main rules are incomplete: $types');
  }
}

bool _sameManagedRuleset(
  Map<String, dynamic> current,
  Map<String, Object> desired,
) {
  final managed = {
    for (final key in [
      'name',
      'target',
      'enforcement',
      'bypass_actors',
      'conditions',
      'rules',
    ])
      key: current[key],
  };
  return jsonEncode(_canonicalize(managed)) ==
      jsonEncode(_canonicalize(desired));
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalize(value[key])};
  }
  if (value is List) return value.map(_canonicalize).toList();
  return value;
}

int _appId(String response, String slug) {
  final app = _jsonObject(jsonDecode(response), slug);
  if (app['slug'] != slug || app['id'] is! int) {
    throw StateError('Could not resolve the $slug GitHub App.');
  }
  return app['id'] as int;
}

Future<String> _ghApi(
  String endpoint, {
  String method = 'GET',
  Map<String, Object>? body,
}) async {
  final process = await Process.start('gh', [
    'api',
    '--method',
    method,
    '-H',
    'X-GitHub-Api-Version: 2022-11-28',
    if (body != null) ...['--input', '-'],
    endpoint,
  ]);
  if (body != null) {
    process.stdin.write(jsonEncode(body));
  }
  await process.stdin.close();
  final stdoutText = await utf8.decoder.bind(process.stdout).join();
  final stderrText = await utf8.decoder.bind(process.stderr).join();
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException('gh', ['api', endpoint], stderrText, exitCode);
  }
  return stdoutText;
}

final class _Options {
  const _Options({
    required this.repository,
    required this.dryRunRunId,
    required this.apply,
  });

  factory _Options.parse(List<String> arguments) {
    var apply = false;
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--apply') {
        apply = true;
        continue;
      }
      if (!argument.startsWith('--') || index + 1 >= arguments.length) {
        throw ArgumentError('Invalid argument: $argument');
      }
      values[argument.substring(2)] = arguments[++index];
    }
    final repository = values['repository'];
    final runId = int.tryParse(values['dry-run-run-id'] ?? '');
    if (repository == null ||
        !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository) ||
        runId == null ||
        runId < 1) {
      throw ArgumentError(
        '--repository OWNER/REPO and --dry-run-run-id ID are required.',
      );
    }
    return _Options(repository: repository, dryRunRunId: runId, apply: apply);
  }

  final String repository;
  final int dryRunRunId;
  final bool apply;
}

Map<String, dynamic> _jsonObject(Object? value, String name) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$name must be an object.');
  }
  return value;
}

List<Map<String, dynamic>> _jsonList(Object? value, String name) {
  if (value is! List) throw FormatException('$name must be a list.');
  return value.map((item) => _jsonObject(item, name)).toList();
}
