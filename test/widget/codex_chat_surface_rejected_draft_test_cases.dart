part of 'codex_chat_surface_test.dart';

void _registerCodexRejectedDraftTests() {
  for (final openingFails in [true, false]) {
    for (final concurrentText in ['', 'Next request']) {
      testWidgets(
        'restores rejected composer ${openingFails ? 'opening' : 'queue'} submission with concurrent text "$concurrentText"',
        (tester) async {
          final rejected = Completer<Object?>();
          final client = _SurfaceRuntimeClient(
            requestHandler: (type, payload) {
              if (type == 'codex.thread.open') {
                if (openingFails) return rejected.future;
                return Future.value({
                  'threadId': 'thread',
                  'chatFeatures': ['codexSharedQueueV1'],
                  'queue': {
                    'threadId': 'thread',
                    'revision': 1,
                    'messages': <Object?>[],
                  },
                  'snapshot': {
                    'timelineCells': <Object?>[],
                    'pendingRequests': <Object?>[],
                  },
                });
              }
              if (type == 'codex.queue.add') return rejected.future;
              return null;
            },
          );
          await _pumpComposerSurface(tester, client);
          final container = ProviderScope.containerOf(
            tester.element(find.byType(CodexChatSurface)),
          );
          final store = container.read(codexComposerDraftStoreProvider);
          const submittedText = r'Inspect @notes and $skill';
          store.restoreSubmission(
            'codex-tab',
            const CodexComposerDraft(
              value: TextEditingValue(text: submittedText),
              attachments: [
                CodexInputAttachment(
                  id: 'notes',
                  path: '/repo/workspace/notes.md',
                  displayName: 'notes.md',
                  isImage: false,
                  origin: CodexInputAttachmentOrigin.mention,
                  tokenText: '@notes',
                  tokenStart: 8,
                ),
              ],
              draftItems: [
                CodexDraftItem(
                  id: 'skill',
                  kind: CodexDraftItemKind.skill,
                  name: 'skill',
                  path: '/repo/workspace/SKILL.md',
                  tokenText: r'$skill',
                  tokenStart: 19,
                ),
              ],
            ),
          );
          await tester.pump();
          final composer = find.byType(TextField).last;
          expect(
            tester.widget<TextField>(composer).controller!.text,
            submittedText,
          );
          await tester.tap(
            find.byKey(const ValueKey<String>('composer-action-button')),
          );
          await tester.pump();
          expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
          if (concurrentText.isNotEmpty) {
            await tester.enterText(composer, concurrentText);
          }
          rejected.completeError(StateError('Submission rejected'));
          await tester.pump();
          await tester.pump();
          final expected = [
            if (concurrentText.isNotEmpty) concurrentText,
            submittedText,
          ].join('\n\n');
          final restored = tester.widget<TextField>(composer).controller!.value;
          expect(restored.text, expected);
          expect(restored.selection.baseOffset, expected.length);
          final offset = concurrentText.isEmpty ? 0 : concurrentText.length + 2;
          expect(
            store.read('codex-tab').attachments.single.tokenStart,
            8 + offset,
          );
          expect(
            store.read('codex-tab').draftItems.single.tokenStart,
            19 + offset,
          );
          await tester.enterText(composer, '$expected!');
          expect(store.read('codex-tab').value.text, '$expected!');
          expect(
            store.read('codex-tab').attachments.single.path,
            '/repo/workspace/notes.md',
          );
          expect(
            store.read('codex-tab').draftItems.single.path,
            '/repo/workspace/SKILL.md',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
