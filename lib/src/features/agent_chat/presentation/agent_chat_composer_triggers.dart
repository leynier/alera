import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/services.dart';

export 'package:alera_agent_chat/alera_agent_chat.dart'
    show AgentChatComposerTrigger, AgentChatComposerTriggerKind;

/// The trigger at the caret of [value]; the rules live in
/// [agentChatComposerTriggerAt], shared with the phone.
AgentChatComposerTrigger? detectAgentChatComposerTrigger(
  TextEditingValue value,
) => value.selection.isValid
    ? agentChatComposerTriggerAt(
        value.text,
        selectionStart: value.selection.start,
        selectionEnd: value.selection.end,
      )
    : null;

/// [value] with [trigger]'s token replaced by [replacement], following
/// [agentChatComposerTriggerReplaced].
TextEditingValue replaceAgentChatComposerTrigger(
  TextEditingValue value,
  AgentChatComposerTrigger trigger, {
  String replacement = '',
}) {
  final replaced = agentChatComposerTriggerReplaced(
    value.text,
    trigger,
    replacement: replacement,
  );
  return TextEditingValue(
    text: replaced.text,
    selection: TextSelection.collapsed(offset: replaced.caret),
  );
}
