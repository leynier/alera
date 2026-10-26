import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/core/errors/user_facing_error_message.dart';
import 'package:alera_mobile/src/design_system/forms/alera_composer_suggestions.dart';
import 'package:alera_mobile/src/design_system/icons/alera_file_icon.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
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

/// A skill, from the `$` suggestions or as `/skill:name` among the commands.
final class const AgentChatComposerSkillEntry(
  final AgentChatProviderSkill skill, {
  final bool fromSlashMenu = false,
}) extends AgentChatComposerMenuEntry;

const String agentChatComposerNoSkillsMessage = 'No matching skill.';
const String agentChatComposerSkillsPendingMessage =
    'Skills appear once the agent starts. Send a message first.';

const String agentChatComposerNoFilesMessage = 'No matching files.';
const String agentChatComposerNoCommandsMessage = 'No matching command.';

/// What the `@`, `/` and `$` suggestions of the chat composer show and do. The
/// trigger rules, the debounced search and the merged command list come from
/// `alera_agent_chat`, shared with the desktop; this follows the field's
/// text, caret and focus, so the suggestions open while the caret is in a
/// trigger token of the focused field and close otherwise. Close hides them
/// until the caret leaves that token. Without a [fileSearch] (a host that
/// has no Quick Open) an `@` is plain text, and without [skills] (a host
/// without `agentChatSkillsV1`) so is a `$`.
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
    this.mentions.addListener(notifyListeners);
    skills?.addListener(_onSkills);
  }

  final TextEditingController text;
  final FocusNode focusNode;
  final AgentChatComposerFileSearch? Function() fileSearch;
  final AgentChatSlashCommandState Function() commandState;
  final ValueChanged<String> onAttach;
  final ValueChanged<AgentChatSlashCommand> onCommand;
  final AgentChatComposerMentionSearch mentions;
  final AgentChatSkillsLoader? skills;

  AgentChatComposerTrigger? _trigger;
  AgentChatComposerTrigger? _dismissed;

  AgentChatComposerTrigger? get trigger => _trigger;

  bool get isOpen => _trigger != null;

  List<AgentChatComposerMenuEntry> get entries => switch (_trigger) {
    null => const <AgentChatComposerMenuEntry>[],
    AgentChatComposerTrigger(kind: .mention) => <AgentChatComposerMenuEntry>[
      for (final path in mentions.results) AgentChatComposerFileEntry(path),
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

  void _onSkills() {
    if (_trigger?.kind == .skill && !_skillsAvailable) {
      _sync();
      return;
    }
    notifyListeners();
  }

  void _sync() {
    final value = text.value;
    var detected = focusNode.hasFocus
        ? agentChatComposerTriggerAt(
            value.text,
            selectionStart: value.selection.start,
            selectionEnd: value.selection.end,
          )
        : null;
    final source = fileSearch();
    if (detected?.kind == .mention && source == null) detected = null;
    if (detected?.kind == .skill && !_skillsAvailable) detected = null;
    final dismissed = _dismissed;
    if (dismissed != null &&
        (detected == null ||
            detected.kind != dismissed.kind ||
            detected.start != dismissed.start)) {
      _dismissed = null;
    }
    final next = _dismissed == null ? detected : null;
    if (next == _trigger) return;
    if (next != null && next.kind != .mention && next.kind != _trigger?.kind) {
      unawaited(skills?.request());
    }
    _trigger = next;
    switch (next) {
      case AgentChatComposerTrigger(kind: .mention, :final query):
        mentions.search(source!, query);
      case _:
        mentions.reset();
    }
    notifyListeners();
  }

  /// Hides the suggestions until the caret leaves the current token.
  void dismiss() {
    _dismissed = _trigger;
    _sync();
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
        _replace(trigger);
        onAttach(source.attachmentPath(relativePath));
      case AgentChatComposerCommandEntry(:final option):
        if (!option.enabled) return;
        _replace(trigger);
        onCommand(option.command);
      case AgentChatComposerProviderCommandEntry(:final command):
        _replace(trigger, command.insertion);
      case AgentChatComposerSkillEntry(:final skill):
        // T3 Code inserts `$name ` from both menus; the runtime adapter
        // rewrites it into the provider's own form when it sends.
        _replace(trigger, skill.insertion);
    }
  }

  void _replace(AgentChatComposerTrigger trigger, [String replacement = '']) {
    final replaced = agentChatComposerTriggerReplaced(
      text.text,
      trigger,
      replacement: replacement,
    );
    text.value = TextEditingValue(
      text: replaced.text,
      selection: TextSelection.collapsed(offset: replaced.caret),
    );
  }

  @override
  void dispose() {
    text.removeListener(_sync);
    focusNode.removeListener(_sync);
    mentions
      ..removeListener(notifyListeners)
      ..dispose();
    skills?.removeListener(_onSkills);
    super.dispose();
  }
}

/// The suggestions of [controller], drawn above the composer box while they
/// are open.
class const AgentChatComposerSuggestionsView({
  super.key,
  required final AgentChatComposerMenuController controller,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.isOpen) return const SizedBox.shrink();
      final kind = controller.trigger?.kind;
      final mention = kind == .mention;
      final skill = kind == .skill;
      final search = controller.mentions;
      final skills = controller.skills;
      return Padding(
        padding: const EdgeInsets.only(bottom: AleraTokens.space6),
        child: AleraComposerSuggestions(
          key: const ValueKey<String>('agent-chat-composer-suggestions'),
          title: mention
              ? 'Files'
              : skill
              ? 'Skills'
              : 'Commands',
          semanticsLabel: mention
              ? 'File Mentions'
              : skill
              ? 'Skills'
              : 'Commands',
          items: <AleraComposerSuggestion>[
            for (final entry in controller.entries) _item(entry),
          ],
          loading:
              (mention && search.loading) ||
              (skill &&
                  skills != null &&
                  skills.loading &&
                  skills.list == null),
          loadingMessage: skill
              ? 'Loading skills…'
              : 'Searching workspace files…',
          emptyMessage: switch (kind) {
            .mention when search.error != null => actionFailureMessage(
              'search workspace files',
              search.error,
            ),
            .mention => agentChatComposerNoFilesMessage,
            .skill => _skillsEmptyMessage(skills),
            _ => agentChatComposerNoCommandsMessage,
          },
          onPick: controller.pick,
          onDismiss: controller.dismiss,
        ),
      );
    },
  );

  static String _skillsEmptyMessage(AgentChatSkillsLoader? skills) {
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

  static Widget _icon(IconData icon) =>
      Icon(icon, size: AleraTokens.iconMd, color: AleraTokens.foregroundMuted);

  static AleraComposerSuggestion _item(AgentChatComposerMenuEntry entry) =>
      switch (entry) {
        AgentChatComposerFileEntry(:final relativePath) => _fileItem(
          relativePath,
        ),
        AgentChatComposerCommandEntry(:final option) => AleraComposerSuggestion(
          id: 'command:${option.command.name}',
          label: option.command.label,
          detail: option.command.description,
          disabledReason: option.disabledReason,
          leading: _icon(switch (option.command) {
            .model => AleraIcons.agent,
            .plan => AleraIcons.plan,
            .standard => AleraIcons.code,
            .usage => AleraIcons.quota,
          }),
        ),
        AgentChatComposerProviderCommandEntry(:final command) =>
          AleraComposerSuggestion(
            id: 'agent-command:${command.name}',
            label: command.label,
            detail: command.detail,
            leading: _icon(AleraIcons.agentCommand),
          ),
        AgentChatComposerSkillEntry(:final skill, :final fromSlashMenu) =>
          AleraComposerSuggestion(
            id: 'skill:${skill.name}',
            label: fromSlashMenu ? '/skill:${skill.name}' : skill.label,
            detail: skill.detail,
            leading: _icon(AleraIcons.skill),
          ),
      };

  static AleraComposerSuggestion _fileItem(String relativePath) {
    // Quick Open answers with the host's separator.
    final separator = relativePath.lastIndexOf(RegExp(r'[/\\]'));
    return AleraComposerSuggestion(
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
