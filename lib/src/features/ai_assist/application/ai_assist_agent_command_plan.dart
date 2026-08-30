part of 'ai_assist_agent_runner.dart';

extension on CliAiAssistAgentRunner {
  Future<_AiAssistAgentCommandPlan> _planCommand(
    AiAssistAgentRunRequest request,
    Map<String, String> environment,
  ) async {
    final settings = request.settings;
    final agent = request.agent ?? settings.agent;
    if (request.accessPolicy == AgentTaskAccessPolicy.diffOnly) {
      requireDiffOnlyAiAssistAgent(agent);
    }
    if (agent == AiAssistAgent.custom) {
      return _planCustomCommand(settings.customCommand, request.prompt);
    }
    final spec = aiAssistAgentSpecs[agent];
    if (spec == null) {
      throw AiAssistException('${agent.label} does not support AI Assist.');
    }
    if (request.outputContract != AgentTaskOutputContract.plainText &&
        request.accessPolicy == AgentTaskAccessPolicy.repositoryReadOnly &&
        (!spec.supportsRepositoryRead || !spec.readOnlyGuarantee)) {
      throw AiAssistException(
        '${spec.label} cannot guarantee read-only repository access for this task.',
      );
    }
    final model = modelForAgent(
      agent,
      request.model ??
          settings.modelFor(agent) ??
          defaultModelIdForAgent(agent, settings),
      extraModels: discoveredModelsForAgent(settings, agent),
    );
    final thinking =
        request.reasoning ??
        settings.thinkingForModel(model.id) ??
        model.defaultThinkingLevel;
    if ((request.outputContract != AgentTaskOutputContract.plainText ||
            spec.promptDelivery == AiPromptDelivery.argv) &&
        utf8.encode(request.prompt).length > spec.maxPromptBytes) {
      throw AiAssistException(
        '${spec.label} cannot receive large prompts safely. Choose an agent that supports stdin prompts or reduce the staged diff.',
      );
    }
    Directory? promptDirectory;
    File? outputFile;
    final environmentOverrides = <String, String>{};
    if (agent == AiAssistAgent.fx) {
      environmentOverrides.addAll(<String, String>{
        'FX_PERMISSION_MODE': 'ask',
        'FX_AUTO_UPGRADE': '0',
        'FX_HERDR': '0',
        if (model.id.trim().isNotEmpty) 'FX_MODEL': model.id.trim(),
      });
    }
    var deliveredPrompt = '';
    if (spec.promptDelivery == AiPromptDelivery.argv) {
      deliveredPrompt = request.prompt;
    } else if (spec.promptDelivery == AiPromptDelivery.promptFile) {
      promptDirectory = await Directory.systemTemp.createTemp(
        'alera-ai-assist-',
      );
      try {
        final promptFile = File(
          '${promptDirectory.path}${Platform.pathSeparator}prompt.txt',
        );
        await promptFile.writeAsString(request.prompt, flush: true);
        deliveredPrompt = promptFile.path;
        if (agent == AiAssistAgent.grok) {
          final grokHome = Directory(p.join(promptDirectory.path, 'grok-home'));
          await grokHome.create();
          await _copyGrokRuntimeConfiguration(
            grokHome,
            environment,
            authenticationOnly:
                request.accessPolicy == AgentTaskAccessPolicy.diffOnly,
          );
          environmentOverrides['GROK_HOME'] = grokHome.path;
        }
      } catch (_) {
        try {
          await promptDirectory.delete(recursive: true);
        } catch (_) {}
        rethrow;
      }
    }
    var args = spec.buildArgs(
      prompt: deliveredPrompt,
      model: model.id,
      thinkingLevel: thinking,
      timeoutSeconds: settings.timeoutSeconds,
    );
    if (request.outputContract != AgentTaskOutputContract.plainText) {
      final schema = request.outputSchema?.trim();
      if (schema == null || schema.isEmpty) {
        throw const AiAssistException(
          'Structured generation requires an output schema.',
        );
      }
      promptDirectory ??= await Directory.systemTemp.createTemp(
        'alera-agent-task-',
      );
      switch (spec.nativeStructuredOutput) {
        case AiNativeStructuredOutput.none:
          break;
        case AiNativeStructuredOutput.codexSchemaFile:
          final schemaFile = File(p.join(promptDirectory.path, 'schema.json'));
          outputFile = File(p.join(promptDirectory.path, 'result.json'));
          await schemaFile.writeAsString(schema, flush: true);
          args = <String>[
            ...args,
            '--output-schema',
            schemaFile.path,
            '--output-last-message',
            outputFile.path,
          ];
        case AiNativeStructuredOutput.claudeJsonSchema:
          _setJsonOutputFormat(args);
          args = <String>[
            ...args,
            '--json-schema',
            schema,
            '--no-session-persistence',
          ];
        case AiNativeStructuredOutput.jsonSchemaArgument:
          _setJsonOutputFormat(args);
          args = <String>[...args, '--json-schema', schema];
      }
    }
    Map<String, String>? exactEnvironment;
    if (request.accessPolicy == AgentTaskAccessPolicy.diffOnly) {
      final authCredentialsStore =
          spec.diffOnlyAccess ==
              AiAssistDiffOnlyAccess.codexRestrictedFilesystem
          ? await codexAuthCredentialsStore(environment)
          : null;
      final execution = planDiffOnlyAiAssistExecution(
        spec: spec,
        arguments: args,
        environment: <String, String>{...environment, ...environmentOverrides},
        codexAuthCredentialsStore: authCredentialsStore,
      );
      args = execution.arguments;
      exactEnvironment = execution.environment;
    }
    return _AiAssistAgentCommandPlan(
      binary: spec.binary,
      args: args,
      stdinPayload: spec.promptDelivery == AiPromptDelivery.stdin
          ? request.prompt
          : null,
      label: spec.label,
      promptDirectory: promptDirectory,
      environmentOverrides: environmentOverrides,
      exactEnvironment: exactEnvironment,
      outputFile: outputFile,
    );
  }

  void _setJsonOutputFormat(List<String> args) {
    final formatIndex = args.indexOf('--output-format');
    if (formatIndex >= 0 && formatIndex + 1 < args.length) {
      args[formatIndex + 1] = 'json';
      return;
    }
    args.addAll(const <String>['--output-format', 'json']);
  }

  Future<void> _copyGrokRuntimeConfiguration(
    Directory isolatedHome,
    Map<String, String> environment, {
    required bool authenticationOnly,
  }) async {
    final configuredHome = environment['GROK_HOME']?.trim();
    final userHome = (environment['HOME'] ?? environment['USERPROFILE'])
        ?.trim();
    final sourceHome = configuredHome != null && configuredHome.isNotEmpty
        ? configuredHome
        : userHome != null && userHome.isNotEmpty
        ? p.join(userHome, '.grok')
        : null;
    if (sourceHome == null) {
      return;
    }
    final fileNames = authenticationOnly
        ? const <String>['auth.json']
        : const <String>[
            'auth.json',
            'config.toml',
            'managed_config.toml',
            'requirements.toml',
          ];
    // Reading Diff excludes configuration that can enable plugins or MCPs.
    for (final fileName in fileNames) {
      final source = File(p.join(sourceHome, fileName));
      if (await source.exists()) {
        await source.copy(p.join(isolatedHome.path, fileName));
      }
    }
  }

  _AiAssistAgentCommandPlan _planCustomCommand(String template, String prompt) {
    final tokens = _tokenizeCommandTemplate(template);
    if (tokens.isEmpty) {
      throw const AiAssistException('Custom command is empty.');
    }
    final usesPlaceholder = tokens.any((token) => token.contains('{prompt}'));
    final substituted = tokens
        .map((token) => token.replaceAll('{prompt}', prompt))
        .toList(growable: false);
    return _AiAssistAgentCommandPlan(
      binary: substituted.first,
      args: substituted.skip(1).toList(growable: false),
      stdinPayload: usesPlaceholder ? null : prompt,
      label: substituted.first,
    );
  }

  List<String> _tokenizeCommandTemplate(String template) {
    final matches = RegExp(r'''"([^"]*)"|'([^']*)'|(\S+)''')
        .allMatches(template);
    return matches
        .map((match) => match.group(1) ?? match.group(2) ?? match.group(3)!)
        .toList(growable: false);
  }
}

Future<void> _deleteTemporaryDirectory(Directory directory) async {
  for (var attempt = 0; attempt < 3; attempt += 1) {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return;
    } catch (_) {
      if (attempt < 2) {
        await Future.pause(const Duration(milliseconds: 100));
      }
    }
  }
}

class const _AiAssistAgentCommandPlan({
  required final String binary,
  required final List<String> args,
  required final String? stdinPayload,
  required final String label,
  final Map<String, String> environmentOverrides = const <String, String>{},
  final Map<String, String>? exactEnvironment,
  final Directory? promptDirectory,
  final File? outputFile,
}) {
  Future<void> dispose() async {
    final directory = promptDirectory;
    if (directory == null) {
      return;
    }
    await _deleteTemporaryDirectory(directory);
  }
}
