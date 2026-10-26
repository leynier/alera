import 'package:alera/src/features/agent_chat/presentation/agent_chat_queued_edit.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatQueueEntry _entry(String id, String text, {int attachments = 0}) =>
    AgentChatQueueEntry(
      queueId: id,
      clientMessageId: 'm-$id',
      text: text,
      createdAt: DateTime.utc(2026, 10, 25),
      attachments: <AgentChatAttachment>[
        for (var i = 0; i < attachments; i++)
          AgentChatAttachment(
            type: AgentChatAttachmentType.file,
            path: '/f$i',
            name: 'f$i',
          ),
      ],
    );

void main() {
  late TerminalComposerController composer;
  late AgentChatQueuedEdit edit;
  setUp(() {
    composer = TerminalComposerController();
    edit = AgentChatQueuedEdit(composer);
    composer.textController.text = 'My draft';
    composer.addPathAttachment(
      '/draft.png',
      kind: TerminalComposerAttachmentKind.image,
    );
  });
  tearDown(() {
    edit.dispose();
    composer.dispose();
  });

  test('editing sets the draft aside and cancel brings it back', () {
    edit.begin(_entry('q1', 'Queued text', attachments: 2));
    expect(edit.queueId, 'q1');
    expect(edit.attachmentCount, 2);
    expect(composer.textController.text, 'Queued text');
    expect(composer.attachments, isEmpty);
    expect(edit.heldDraft!.text, 'My draft');

    edit.cancel();
    expect(edit.isEditing, isFalse);
    expect(edit.heldDraft, isNull);
    expect(composer.textController.text, 'My draft');
    expect(composer.attachments.single.path, '/draft.png');
  });

  test('a saved edit sends the field text and restores the draft', () async {
    edit.begin(_entry('q1', 'Queued text'));
    composer.textController.text = 'Edited text';
    final saved = <(String, String)>[];
    final error = await edit.save((queueId, text) async {
      saved.add((queueId, text));
      return null;
    });
    expect(error, isNull);
    expect(saved, <(String, String)>[('q1', 'Edited text')]);
    expect(edit.isEditing, isFalse);
    expect(composer.textController.text, 'My draft');
  });

  test('a refused save keeps the edit open with its text', () async {
    edit.begin(_entry('q1', 'Queued text'));
    composer.textController.text = 'Edited text';
    final error = await edit.save((_, _) async => 'Gone.');
    expect(error, 'Gone.');
    expect(edit.queueId, 'q1');
    expect(composer.textController.text, 'Edited text');
  });

  test('an empty edit without attachments is not sent', () async {
    edit.begin(_entry('q1', 'Queued text'));
    composer.textController.clear();
    var calls = 0;
    final error = await edit.save((_, _) async {
      calls += 1;
      return null;
    });
    expect(error, isNotNull);
    expect(calls, 0);
  });

  test('switching edits keeps the first draft and files added since', () {
    edit.begin(_entry('q1', 'First'));
    composer.addPathAttachment('/added.txt');
    edit.begin(_entry('q2', 'Second'));
    expect(composer.textController.text, 'Second');
    expect(composer.attachments, isEmpty);
    edit.cancel();
    expect(composer.textController.text, 'My draft');
    expect(composer.attachments.map((attachment) => attachment.path), <String>[
      '/draft.png',
      '/added.txt',
    ]);
  });

  test('a message that left the queue ends the edit', () {
    edit.begin(_entry('q1', 'Queued text'));
    expect(
      edit.reconcile(<AgentChatQueueEntry>[_entry('q1', 'Queued text')]),
      AgentChatQueuedEditLoss.none,
    );
    expect(edit.isEditing, isTrue);

    composer.textController.text = 'Changed';
    expect(
      edit.reconcile(const <AgentChatQueueEntry>[]),
      AgentChatQueuedEditLoss.discarded,
    );
    expect(composer.textController.text, 'My draft');
  });

  test('a changed edit becomes the draft when there was none', () {
    composer.textController.clear();
    composer.removeAttachments(<String>[
      for (final attachment in composer.attachments) attachment.id,
    ]);
    edit.begin(_entry('q1', 'Queued text'));
    composer.textController.text = 'Changed';
    expect(
      edit.reconcile(const <AgentChatQueueEntry>[]),
      AgentChatQueuedEditLoss.kept,
    );
    expect(edit.isEditing, isFalse);
    expect(composer.textController.text, 'Changed');
  });
}
