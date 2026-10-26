import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_composer_menu.dart';
import 'package:alera/src/design_system/forms/alera_ime_composition_key_guard.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_triggers.dart';
import 'package:alera/src/features/error_reporting/application/user_facing_error_message.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// A row of the composer menu: a workspace file, a local command, a command
/// the agent advertises or one of its skills.
sealed class AgentChatComposerMenuEntry {
  const AgentChatComposerMenuEntry();
}

final class const AgentChatComposerFileEntry(final String relativePath)
    extends AgentChatComposerMenuEntry;

final class const AgentChatComposerCommandEntry(
  final AgentChatSlashCommandOption option,
) extends AgentChatComposerMenuEntry;

final class const AgentChatComposerProviderCommandEntry(
  final AgentChatProviderCommand command,
) extends AgentChatComposerMenuEntry;

/// A skill, from the `$` menu or as `/skill:name` in the `/` menu.
final class const AgentChatComposerSkillEntry(
  final AgentChatProviderSkill skill, {
  final bool fromSlashMenu = false,
}) extends AgentChatComposerMenuEntry;

const String agentChatComposerNoSkillsMessage = 'No matching skill.';
const String agentChatComposerSkillsPendingMessage =
    'Skills appear once the agent starts. Send a message first.';
const String agentChatComposerSkillsLoadingMessage = 'Loading skills…';

const String agentChatComposerNoFileSearchMessage =
    'File mentions need a workspace to search.';
const String agentChatComposerNoFilesMessage = 'No matching files.';
const String agentChatComposerNoCommandsMessage = 'No matching command.';

/// What the `@`, `/` and `$` menu of the chat composer shows and does. It follows
/// the field's text, caret and focus, so it opens while the caret is in a
/// trigger token of a focused field and closes otherwise; Escape closes it
/// until the caret leaves that token. The field forwards its keys through
/// [handleKey] first, so the menu sees Up, Down, Enter, Tab and Escape before
/// history, send and stop do.
class AgentChatComposerMenuController extends ChangeNotifier {
  AgentChatComposerMenuController({
    required this.text,
    required this.focusNode,
    required this.fileSearch,
    required this.commandState,
    required this.onAttach,
    required this.onCommand,
    AgentChatComposerMentionSearch? mentions,
    this.skills,
  }) : mentions = mentions ?? AgentChatComposerMentionSearch() {
    text.addListener(_sync);
    focusNode.addListener(_sync);
    this.mentions.addListener(_onResults);
    skills?.addListener(_onSkills);
  }

  final TextEditingController text;
  final FocusNode focusNode;
  final AgentChatComposerFileSearch? Function() fileSearch;
  final AgentChatSlashCommandState Function() commandState;
  final ValueChanged<String> onAttach;
  final ValueChanged<AgentChatSlashCommand> onCommand;
  final AgentChatComposerMentionSearch mentions;

  /// The chat's skills; without it, or on a runtime without them, `$` stays
  /// plain text.
  final AgentChatSkillsLoader? skills;

  AgentChatComposerTrigger? _trigger;
  AgentChatComposerTrigger? _dismissed;
  int _active = 0;

  AgentChatComposerTrigger? get trigger => _trigger;

  bool get isOpen => _trigger != null;

  int get activeIndex => _active;

  List<AgentChatComposerMenuEntry> get entries => switch (_trigger) {
    null => const <AgentChatComposerMenuEntry>[],
    AgentChatComposerTrigger(kind: .mention) =>
      fileSearch() == null
          ? const <AgentChatComposerMenuEntry>[]
          : <AgentChatComposerMenuEntry>[
              for (final path in mentions.results)
                AgentChatComposerFileEntry(path),
            ],
    AgentChatComposerTrigger(kind: .command, :final query, :final start) =>
      <AgentChatComposerMenuEntry>[
        for (final entry in agentChatSlashMenuEntries(
          commandState(),
          query: query,
          atPromptStart: start == 0,
        ))
          switch (entry) {
            AgentChatSlashMenuLocalCommand(:final option) =>
              AgentChatComposerCommandEntry(option),
            AgentChatSlashMenuProviderCommand(:final command) =>
              AgentChatComposerProviderCommandEntry(command),
            AgentChatSlashMenuSkill(:final skill) =>
              AgentChatComposerSkillEntry(skill, fromSlashMenu: true),
          },
      ],
    AgentChatComposerTrigger(kind: .skill, :final query) =>
      <AgentChatComposerMenuEntry>[
        for (final skill in agentChatSearchProviderSkills(
          skills?.skills ?? const <AgentChatProviderSkill>[],
          query,
        ))
          AgentChatComposerSkillEntry(skill),
      ],
  };

  bool get _skillsAvailable => skills != null && !skills!.unsupported;

  void _sync() {
    final found = focusNode.hasFocus
        ? detectAgentChatComposerTrigger(text.value)
        : null;
    final detected = found?.kind == .skill && !_skillsAvailable ? null : found;
    final dismissed = _dismissed;
    if (dismissed != null &&
        (detected == null ||
            detected.kind != dismissed.kind ||
            detected.start != dismissed.start)) {
      _dismissed = null;
    }
    final next = _dismissed == null ? detected : null;
    final previous = _trigger;
    if (next == previous) return;
    _trigger = next;
    if (next?.kind != previous?.kind || next?.query != previous?.query) {
      _active = 0;
    }
    if (next != null && next.kind != .mention && next.kind != previous?.kind) {
      // Each time a menu opens it asks again, so a skill added meanwhile
      // shows; the loader keeps a fresh answer and the runtime its cache.
      unawaited(skills?.request());
    }
    switch (next) {
      case AgentChatComposerTrigger(kind: .mention, :final query):
        final source = fileSearch();
        if (source == null) {
          mentions.reset();
        } else {
          mentions.search(source, query);
        }
      case _:
        mentions.reset();
    }
    notifyListeners();
  }

  void _onSkills() {
    if (_trigger == null && !_skillsAvailable) return;
    if (_trigger?.kind == .skill && !_skillsAvailable) {
      _sync();
      return;
    }
    _onResults();
  }

  void _onResults() {
    final count = entries.length;
    if (_active >= count) _active = 0;
    notifyListeners();
  }

  void highlight(int index) {
    if (index == _active) return;
    _active = index;
    notifyListeners();
  }

  void dismiss() {
    _dismissed = _trigger;
    _sync();
  }

  KeyEventResult handleKey(KeyEvent event) {
    if (!isOpen || AleraImeCompositionKeyGuard.isComposing(text.value)) {
      return KeyEventResult.ignored;
    }
    final key = AleraComposerMenu.keyFor(event);
    if (key == null) return KeyEventResult.ignored;
    if (key == AleraComposerMenuKey.dismiss) {
      dismiss();
      return KeyEventResult.handled;
    }
    final count = entries.length;
    if (count > 0) {
      switch (key) {
        case AleraComposerMenuKey.previous:
          highlight(AleraComposerMenu.step(_active, count, -1));
        case AleraComposerMenuKey.next:
          highlight(AleraComposerMenu.step(_active, count, 1));
        case AleraComposerMenuKey.pick:
          pick(_active);
        case AleraComposerMenuKey.dismiss:
          break;
      }
      return KeyEventResult.handled;
    }
    // Enter while the first results are on their way would send the
    // half-typed mention.
    return key == AleraComposerMenuKey.pick &&
            _trigger?.kind == .mention &&
            mentions.loading
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// Picks the row at [index]: a file is attached and a local command runs,
  /// and either way its token leaves the prompt. An agent command replaces
  /// the token with `/name ` for the person to finish, since the agent
  /// expands it when the prompt is sent. A disabled command does nothing.
  void pick(int index) {
    final trigger = _trigger;
    final entries = this.entries;
    if (trigger == null || index < 0 || index >= entries.length) return;
    switch (entries[index]) {
      case AgentChatComposerFileEntry(:final relativePath):
        final source = fileSearch();
        if (source == null) return;
        text.value = replaceAgentChatComposerTrigger(text.value, trigger);
        onAttach(source.attachmentPath(relativePath));
      case AgentChatComposerCommandEntry(:final option):
        if (!option.enabled) return;
        text.value = replaceAgentChatComposerTrigger(text.value, trigger);
        onCommand(option.command);
      case AgentChatComposerProviderCommandEntry(:final command):
        text.value = replaceAgentChatComposerTrigger(
          text.value,
          trigger,
          replacement: command.insertion,
        );
      case AgentChatComposerSkillEntry(:final skill):
        // T3 Code inserts `$name ` from both menus; the runtime adapter
        // rewrites it into the provider's own form when it sends.
        text.value = replaceAgentChatComposerTrigger(
          text.value,
          trigger,
          replacement: skill.insertion,
        );
    }
  }

  @override
  void dispose() {
    text.removeListener(_sync);
    focusNode.removeListener(_sync);
    mentions
      ..removeListener(_onResults)
      ..dispose();
    skills?.removeListener(_onSkills);
    super.dispose();
  }
}

/// Shows the composer menu of [controller] over [child], the composer box.
class const AgentChatComposerMenuOverlay({
  super.key,
  required final AgentChatComposerMenuController controller,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) => AleraComposerMenuAnchor(
      key: const ValueKey<String>('agent-chat-composer-menu-anchor'),
      open: controller.isOpen,
      // The composer box sits inside AleraComposer's own padding.
      inset: const EdgeInsets.all(AleraTokens.space12),
      menu: controller.isOpen ? _menu() : const SizedBox.shrink(),
      child: child!,
    ),
    child: child,
  );

  Widget _menu() {
    final kind = controller.trigger?.kind;
    final mention = kind == .mention;
    final skill = kind == .skill;
    final search = controller.mentions;
    final skills = controller.skills;
    final entries = controller.entries;
    return AleraComposerMenu(
      key: const ValueKey<String>('agent-chat-composer-menu'),
      semanticsLabel: mention
          ? 'File Mentions'
          : skill
          ? 'Skills'
          : 'Commands',
      title: mention
          ? 'Files'
          : skill
          ? 'Skills'
          : 'Commands',
      items: <AleraComposerMenuItem>[for (final entry in entries) _item(entry)],
      activeIndex: controller.activeIndex,
      loading:
          (mention && search.loading) ||
          (skill && skills != null && skills.loading && skills.list == null),
      loadingMessage: skill
          ? agentChatComposerSkillsLoadingMessage
          : 'Searching workspace files…',
      emptyMessage: switch (kind) {
        .mention when controller.fileSearch() == null =>
          agentChatComposerNoFileSearchMessage,
        .mention when search.error != null => actionFailureMessage(
          'search workspace files',
          search.error,
        ),
        .mention => agentChatComposerNoFilesMessage,
        .skill => agentChatComposerSkillsEmptyMessage(skills),
        _ => agentChatComposerNoCommandsMessage,
      },
      onActiveChanged: controller.highlight,
      onPick: controller.pick,
    );
  }

  static AleraComposerMenuItem _item(AgentChatComposerMenuEntry entry) =>
      switch (entry) {
        AgentChatComposerFileEntry(:final relativePath) => _fileItem(
          relativePath,
        ),
        AgentChatComposerCommandEntry(:final option) => AleraComposerMenuItem(
          id: 'command:${option.command.name}',
          label: option.command.label,
          detail: option.command.description,
          disabledReason: option.disabledReason,
          leading: Icon(
            switch (option.command) {
              .model => AleraIcons.agent,
              .plan => AleraIcons.plan,
              .standard => AleraIcons.code,
              .usage => AleraIcons.quota,
            },
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundMuted,
          ),
        ),
        AgentChatComposerProviderCommandEntry(:final command) =>
          AleraComposerMenuItem(
            id: 'agent-command:${command.name}',
            label: command.label,
            detail: command.detail,
            leading: const Icon(
              AleraIcons.agentCommand,
              size: AleraTokens.iconMd,
              color: AleraTokens.foregroundMuted,
            ),
          ),
        AgentChatComposerSkillEntry(:final skill, :final fromSlashMenu) =>
          AleraComposerMenuItem(
            id: 'skill:${skill.name}',
            // T3 Code labels a skill by name in the `/` menu, where it
            // reads as a command, and by its display name in the `$` menu.
            label: fromSlashMenu ? '/skill:${skill.name}' : skill.label,
            detail: skill.detail,
            leading: const Icon(
              AleraIcons.skill,
              size: AleraTokens.iconMd,
              color: AleraTokens.foregroundMuted,
            ),
          ),
      };

  static AleraComposerMenuItem _fileItem(String relativePath) {
    // Workspace file paths come from the native index with either
    // separator, as in Quick Open.
    final separator = relativePath.lastIndexOf(RegExp(r'[/\\]'));
    return AleraComposerMenuItem(
      id: 'file:$relativePath',
      label: relativePath.substring(separator + 1),
      detail: separator < 0 ? null : relativePath.substring(0, separator),
      leading: AleraFileIcon(
        pathOrName: relativePath,
        kind: .file,
        size: AleraTokens.iconMd,
      ),
    );
  }
}

/// Why the `$` menu has no rows: the agent reports skills only once it
/// starts, discovery failed, or nothing matches.
String agentChatComposerSkillsEmptyMessage(AgentChatSkillsLoader? skills) {
  final list = skills?.list;
  if (list == null && skills?.error != null) {
    return actionFailureMessage('load the skills', skills!.error);
  }
  return switch (list?.status) {
    AgentChatSkillsStatus.pending => agentChatComposerSkillsPendingMessage,
    AgentChatSkillsStatus.failed =>
      list!.error ?? 'The skills could not be loaded.',
    _ => agentChatComposerNoSkillsMessage,
  };
}

/// What the composer's commands act on.
final class const AgentChatSlashCommandTargets({
  required final AleraPopoverController modelPicker,
  required final AleraPopoverController usage,
  required final ValueChanged<AgentChatConfiguration> onConfigure,
}) {
  void run(AgentChatSlashCommand command) {
    switch (command) {
      case AgentChatSlashCommand.model:
        modelPicker.open();
      case AgentChatSlashCommand.usage:
        usage.open();
      case AgentChatSlashCommand.plan || AgentChatSlashCommand.standard:
        onConfigure(
          AgentChatConfiguration(
            interactionMode: agentChatSlashCommandInteractionMode(command),
          ),
        );
    }
  }
}

/// The command state of a chat's composer: the model picker and mode
/// commands follow the footer controls, and `/usage` the usage ring.
AgentChatSlashCommandState agentChatSlashCommandState(
  AgentChatComposerSettings settings,
  AgentChatUsage usage, {
  List<AgentChatProviderSkill> skills = const <AgentChatProviderSkill>[],
}) => AgentChatSlashCommandState(
  modelPickerAvailable:
      settings.catalog == AgentChatCatalogState.ready && !settings.configuring,
  modelPickerBlockedReason: switch (settings.catalog) {
    AgentChatCatalogState.loading => 'The agents are still loading.',
    AgentChatCatalogState.failed => 'The agents could not be loaded.',
    AgentChatCatalogState.ready => agentChatSlashCommandConfiguringReason,
  },
  planModeSupported: agentChatPlanModeSupported(settings),
  interactionMode: settings.session.interactionMode,
  configuring: settings.configuring,
  usageAvailable: usage.contextFraction != null || usage.windows.isNotEmpty,
  providerCommands: settings.session.commands,
  providerSkills: skills,
);
