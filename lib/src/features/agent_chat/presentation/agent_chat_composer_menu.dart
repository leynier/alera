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

/// A row of the composer menu: a workspace file, a local command or a
/// command the agent advertises.
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

const String agentChatComposerNoFileSearchMessage =
    'File mentions need a workspace to search.';
const String agentChatComposerNoFilesMessage = 'No matching files.';
const String agentChatComposerNoCommandsMessage = 'No matching command.';

/// What the `@` and `/` menu of the chat composer shows and does. It follows
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
  }) : mentions = mentions ?? AgentChatComposerMentionSearch() {
    text.addListener(_sync);
    focusNode.addListener(_sync);
    this.mentions.addListener(_onResults);
  }

  final TextEditingController text;
  final FocusNode focusNode;
  final AgentChatComposerFileSearch? Function() fileSearch;
  final AgentChatSlashCommandState Function() commandState;
  final ValueChanged<String> onAttach;
  final ValueChanged<AgentChatSlashCommand> onCommand;
  final AgentChatComposerMentionSearch mentions;

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
    AgentChatComposerTrigger(kind: .command, :final query) =>
      <AgentChatComposerMenuEntry>[
        for (final entry in agentChatSlashMenuEntries(
          commandState(),
          query: query,
        ))
          switch (entry) {
            AgentChatSlashMenuLocalCommand(:final option) =>
              AgentChatComposerCommandEntry(option),
            AgentChatSlashMenuProviderCommand(:final command) =>
              AgentChatComposerProviderCommandEntry(command),
          },
      ],
  };

  void _sync() {
    final detected = focusNode.hasFocus
        ? detectAgentChatComposerTrigger(text.value)
        : null;
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
    }
  }

  @override
  void dispose() {
    text.removeListener(_sync);
    focusNode.removeListener(_sync);
    mentions
      ..removeListener(_onResults)
      ..dispose();
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
    final mention = controller.trigger?.kind == .mention;
    final search = controller.mentions;
    final entries = controller.entries;
    return AleraComposerMenu(
      key: const ValueKey<String>('agent-chat-composer-menu'),
      semanticsLabel: mention ? 'File Mentions' : 'Commands',
      title: mention ? 'Files' : 'Commands',
      items: <AleraComposerMenuItem>[for (final entry in entries) _item(entry)],
      activeIndex: controller.activeIndex,
      loading: mention && search.loading,
      loadingMessage: 'Searching workspace files…',
      emptyMessage: switch (mention) {
        true when controller.fileSearch() == null =>
          agentChatComposerNoFileSearchMessage,
        true when search.error != null => actionFailureMessage(
          'search workspace files',
          search.error,
        ),
        true => agentChatComposerNoFilesMessage,
        false => agentChatComposerNoCommandsMessage,
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
  AgentChatUsage usage,
) => AgentChatSlashCommandState(
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
);
