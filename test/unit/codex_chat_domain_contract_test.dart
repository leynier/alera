import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_composer_draft.dart';
import 'package:alera/src/features/codex_chat/domain/codex_file_reference.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

CodexTimelineCell _cell(String id, String kind, String text) =>
    CodexTimelineCell.fromJson(<String, Object?>{
      'id': id,
      'kind': kind,
      'markdownText': text,
      'status': 'completed',
    });

void main() {
  test('attachment and draft copies preserve identity and replace fields', () {
    const attachment = CodexInputAttachment(
      id: 'attachment',
      path: 'docs/read me.md',
      isImage: false,
      mimeType: 'text/markdown',
      displayName: 'read me.md',
      sizeBytes: 10,
      detail: 'high',
      origin: CodexInputAttachmentOrigin.mention,
      tokenText: '@docs/read me.md',
      tokenStart: 4,
    );
    final copiedAttachment = attachment.copyWith(
      sizeBytes: 20,
      isDirectory: true,
    );
    expect(copiedAttachment.id, attachment.id);
    expect(copiedAttachment.path, attachment.path);
    expect(copiedAttachment.mimeType, attachment.mimeType);
    expect(copiedAttachment.displayName, attachment.displayName);
    expect(copiedAttachment.detail, attachment.detail);
    expect(copiedAttachment.origin, attachment.origin);
    expect(copiedAttachment.tokenText, attachment.tokenText);
    expect(copiedAttachment.tokenStart, attachment.tokenStart);
    expect(copiedAttachment.sizeBytes, 20);
    expect(copiedAttachment.isDirectory, isTrue);
    final unchangedAttachment = attachment.copyWith();
    expect(unchangedAttachment.sizeBytes, attachment.sizeBytes);
    expect(unchangedAttachment.isDirectory, attachment.isDirectory);

    const item = CodexDraftItem(
      id: 'skill',
      kind: CodexDraftItemKind.skill,
      name: 'Review',
      path: '/skills/review',
      tokenText: r'$Review',
      tokenStart: 2,
      iconUrl: 'https://example.test/icon.png',
    );
    final copiedItem = item.copyWith(tokenStart: 8);
    expect(copiedItem.id, item.id);
    expect(copiedItem.kind, item.kind);
    expect(copiedItem.name, item.name);
    expect(copiedItem.path, item.path);
    expect(copiedItem.tokenText, item.tokenText);
    expect(copiedItem.tokenStart, 8);
    expect(copiedItem.iconUrl, item.iconUrl);
    expect(item.copyWith().tokenStart, item.tokenStart);
  });

  test('composer drafts preserve omitted values and report content', () {
    const empty = CodexComposerDraft();
    expect(empty.isEmpty, isTrue);

    final draft = empty.copyWith(
      value: const TextEditingValue(text: 'Inspect'),
      attachments: const <CodexInputAttachment>[
        CodexInputAttachment(path: 'a.txt', isImage: false),
      ],
      draftItems: const <CodexDraftItem>[
        CodexDraftItem(
          id: 'app',
          kind: CodexDraftItemKind.app,
          name: 'GitHub',
          path: 'github',
        ),
      ],
    );
    expect(draft.isEmpty, isFalse);
    final unchanged = draft.copyWith();
    expect(unchanged.value, draft.value);
    expect(identical(unchanged.attachments, draft.attachments), isTrue);
    expect(identical(unchanged.draftItems, draft.draftItems), isTrue);
  });

  test('file reference ranges choose the closest repeated token', () {
    expect(codexFileReferenceText(' docs/read me.md '), '"docs/read me.md"');
    expect(codexFileReferenceText('a" b'), 'a" b');
    expect(codexFileReferenceRange('plain', ''), isNull);
    expect(codexFileReferenceRange('plain', 'missing'), isNull);
    expect(codexFileReferenceRange('README.md then README.md', 'README.md'), (
      start: 0,
      end: 10,
    ));
    expect(
      codexFileReferenceRange(
        'README.md then README.md ',
        'README.md',
        preferredStart: 18,
      ),
      (start: 15, end: 25),
    );
  });

  test('thread models cover compatibility fallbacks and pagination', () {
    final cwd = CodexCwdOption.fromJson(<String, Object?>{
      'workspaceId': 7,
      'path': '/repo',
    });
    expect(
      cwd,
      const CodexCwdOption(workspaceId: '7', name: '/repo', path: '/repo'),
    );
    expect(cwd.hashCode, cwd.hashCode);
    expect(
      cwd ==
          const CodexCwdOption(workspaceId: '8', name: '/repo', path: '/repo'),
      isFalse,
    );

    final thread = CodexThreadSummary.fromJson(<String, Object?>{
      'threadId': 9,
      'name': 'Named thread',
      'preview': 'Preview',
      'cwd': '/repo',
      'workspaceId': 'workspace',
      'workspaceName': 'Workspace',
      'sourceKind': 'cli',
      'status': <String, Object?>{'type': 'idle'},
      'createdAt': '2026-08-10T12:00:00Z',
      'updatedAt': 'invalid',
      'recencyAt': Object(),
      'isPinned': true,
      'boundTabId': 'tab',
      'boundWorkspaceId': 'workspace',
      'canResume': false,
    });
    expect(thread.id, '9');
    expect(thread.title, 'Named thread');
    expect(thread.createdAt, DateTime.utc(2026, 8, 10, 12));
    expect(thread.updatedAt, isNull);
    expect(thread.recencyAt, isNull);
    expect(thread.isPinned, isTrue);
    expect(thread.isBound, isTrue);
    expect(thread.canResume, isFalse);
    expect(CodexThreadSummary.fromJson(null).title, 'Untitled Codex Thread');

    final first = CodexThreadPage.fromJson(<String, Object?>{
      'threads': <Object?>[
        <String, Object?>{'id': 'first', 'preview': 'First'},
      ],
      'nextCursor': 'next-1',
      'backwardsCursor': 'back',
      'cwdOptions': <Object?>[
        <String, Object?>{
          'workspaceId': 'workspace',
          'name': 'Workspace',
          'path': '/repo',
        },
      ],
    });
    final next = CodexThreadPage.fromJson(<String, Object?>{
      'data': <Object?>[
        <String, Object?>{'id': 'second', 'title': 'Second'},
      ],
      'nextCursor': 'next-2',
    });
    final combined = first.append(next);
    expect(combined.items.map((item) => item.id), <String>['first', 'second']);
    expect(combined.nextCursor, 'next-2');
    expect(combined.backwardsCursor, 'back');
    expect(combined.cwdOptions, first.cwdOptions);

    final history = CodexThreadHistoryPage.fromJson(<String, Object?>{
      'snapshot': <String, Object?>{'title': 'History'},
      'data': <Object?>[
        <String, Object?>{'id': 'item'},
        'ignored',
      ],
      'nextCursor': 'next',
      'backwardsCursor': 'back',
      'cwd': '/repo',
    });
    expect(history.snapshot.title, 'History');
    expect(history.items, <Map<String, Object?>>[
      <String, Object?>{'id': 'item'},
    ]);
    expect(history.nextCursor, 'next');
    expect(history.backwardsCursor, 'back');
    expect(history.cwd, '/repo');
  });

  test('segmented timelines expose immutable history and live access', () {
    final historyCell = _cell('history', 'userMessage', 'Earlier prompt');
    final liveCell = _cell('live', 'userMessage', 'Current prompt');
    final timeline = CodexTimelineCells.segmented(
      history: <CodexTimelineCell>[historyCell],
      live: <CodexTimelineCell>[liveCell],
    );
    expect(timeline.history, <CodexTimelineCell>[historyCell]);
    expect(timeline.live, <CodexTimelineCell>[liveCell]);
    expect(timeline.historyPromptHistory, <String>['Earlier prompt']);
    expect(timeline.historyIndexes, <String, int>{'history': 0});
    expect(timeline.historyIndexFor('history'), 0);
    expect(timeline[0], historyCell);
    expect(timeline[1], liveCell);
    expect(() => timeline.length = 3, throwsUnsupportedError);
    expect(() => timeline[0] = liveCell, throwsUnsupportedError);

    final prompts = timeline.promptHistoryWithLive(<CodexTimelineCell>[
      liveCell,
    ]);
    expect(prompts, <String>['Earlier prompt', 'Current prompt']);
    expect((prompts as dynamic).history, <String>['Earlier prompt']);
    expect(() => prompts.length = 3, throwsUnsupportedError);
    expect(() => prompts[0] = 'Changed', throwsUnsupportedError);
  });

  test('snapshot deltas update and remove segmented history', () {
    final historyUser = _cell('history-user', 'userMessage', 'Earlier prompt');
    final historyAssistant = _cell(
      'history-assistant',
      'assistantMessage',
      'Earlier answer',
    );
    final live = _cell('live', 'assistantMessage', 'Live answer');
    final snapshot = CodexChatSnapshot(
      events: <CodexTimelineEvent>[
        CodexTimelineEvent.fromJson(<String, Object?>{'method': 'old'}),
      ],
      timelineCells: CodexTimelineCells.segmented(
        history: <CodexTimelineCell>[historyUser, historyAssistant],
        live: <CodexTimelineCell>[live],
      ),
      promptHistory: const <String>['Earlier prompt'],
      pendingRequests: const <CodexPendingRequest>[
        CodexPendingRequest(
          id: 1,
          method: 'request',
          params: <String, Object?>{},
        ),
      ],
      contextLimit: 100,
    );

    final updated = snapshot.applyDelta(<String, Object?>{
      'timelineRemovedIds': <String>['history-user', 'live'],
      'timelineUpserts': <Object?>[
        <String, Object?>{
          'id': 'history-assistant',
          'kind': 'assistantMessage',
          'markdownText': 'Updated answer',
        },
        <String, Object?>{
          'id': 'new-user',
          'kind': 'userMessage',
          'markdownText': 'New prompt',
        },
      ],
      'eventsAppend': <Object?>[
        <String, Object?>{'method': 'new-1'},
        <String, Object?>{'method': 'new-2'},
      ],
      'eventLimit': 1,
      'pendingRequests': <Object?>[
        <String, Object?>{'id': 2, 'method': 'question'},
      ],
      'contextLimit': 200,
    });

    expect(updated.timelineCells.map((cell) => cell.id), <String>[
      'history-assistant',
      'new-user',
    ]);
    expect(updated.timelineCells.first.markdownText, 'Updated answer');
    expect(updated.promptHistory, <String>['New prompt']);
    expect(updated.events.single.method, 'new-2');
    expect(updated.pendingRequests.single.id, 2);
    expect(updated.contextLimit, 200);

    final historyOnlyUpdate = snapshot.applyDelta(<String, Object?>{
      'timelineUpserts': <Object?>[
        <String, Object?>{
          'id': 'history-assistant',
          'kind': 'assistantMessage',
          'markdownText': 'History-only update',
        },
      ],
    });
    expect(
      historyOnlyUpdate.timelineCells[1].markdownText,
      'History-only update',
    );
  });

  test('approval amendments preserve current and legacy wire contracts', () {
    final command = CodexPendingRequest(
      id: 1,
      method: 'execCommandApproval',
      params: <String, Object?>{
        'proposed_execpolicy_amendment': <Object?>['git', 'status'],
        'proposed_network_policy_amendments': <Object?>[
          <String, Object?>{'host': 'example.test'},
          'ignored',
        ],
      },
    );
    final execDecision = command.approvalDecisionValue(
      'acceptWithExecpolicyAmendment',
    );
    expect(
      command.supportsApprovalDecision('acceptWithExecpolicyAmendment'),
      isTrue,
    );
    expect(command.approvalWireDecision(execDecision), <String, Object?>{
      'approved_execpolicy_amendment': <String, Object?>{
        'proposed_execpolicy_amendment': <Object?>['git', 'status'],
      },
    });

    final network = CodexPendingRequest(
      id: 2,
      method: 'execCommandApproval',
      params: <String, Object?>{
        'proposedNetworkPolicyAmendments': <Object?>[
          <String, Object?>{'host': 'example.test'},
        ],
      },
    );
    final networkDecision = network.approvalDecisionValue(
      'applyNetworkPolicyAmendment',
    );
    expect(
      network.supportsApprovalDecision('applyNetworkPolicyAmendment'),
      isTrue,
    );
    expect(network.approvalWireDecision(networkDecision), <String, Object?>{
      'network_policy_amendment': <String, Object?>{
        'network_policy_amendment': <String, Object?>{'host': 'example.test'},
      },
    });

    expect(
      command.approvalWireDecision(<String, Object?>{}),
      <String, Object?>{},
    );
    expect(
      command.approvalWireDecision(<String, Object?>{
        'acceptWithExecpolicyAmendment': 'invalid',
      }),
      <String, Object?>{'acceptWithExecpolicyAmendment': 'invalid'},
    );
    expect(
      network.approvalWireDecision(<String, Object?>{
        'applyNetworkPolicyAmendment': <String, Object?>{
          'network_policy_amendment': 'invalid',
        },
      }),
      <String, Object?>{
        'applyNetworkPolicyAmendment': <String, Object?>{
          'network_policy_amendment': 'invalid',
        },
      },
    );
  });

  test('compaction completion updates one row and preserves neighbors', () {
    final now = DateTime.utc(2026, 8, 10, 12);
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[_cell('neighbor', 'assistantMessage', 'Keep me')],
      <String, Object?>{
        'method': 'item/started',
        'params': <String, Object?>{
          'turnId': 'turn',
          'item': <String, Object?>{
            'id': 'compact',
            'type': 'contextCompaction',
          },
        },
      },
      now: now,
    );
    cells = CodexTimelineReducer.reduce(cells, <String, Object?>{
      'method': 'thread/compacted',
      'params': <String, Object?>{'turnId': 'turn'},
    }, now: now.add(const Duration(seconds: 1)));
    expect(cells.first.id, 'neighbor');
    expect(cells.last.title, 'Compacted');

    var legacyCells = CodexTimelineReducer.reduce(
      const <CodexTimelineCell>[],
      <String, Object?>{
        'method': 'contextCompaction/outputDelta',
        'params': <String, Object?>{
          'turnId': 'legacy-turn',
          'type': 'contextCompaction',
          'delta': 'Compacting context',
        },
      },
      now: now,
    );
    expect(legacyCells.single.title, 'Compacting');
    legacyCells = CodexTimelineReducer.reduce(legacyCells, <String, Object?>{
      'method': 'contextCompaction/completedOutputDelta',
      'params': <String, Object?>{
        'turnId': 'legacy-turn',
        'type': 'contextCompaction',
        'delta': 'Context compacted',
      },
    }, now: now);
    expect(legacyCells.last.title, 'Compacted');
  });
}
