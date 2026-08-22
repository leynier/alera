part of 'codex_chat_timeline_test.dart';

void registerCodexTimelineLegacyTests(DateTime now) {
  test('restores legacy item completion and task messages', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _message('codex/event/item_started', <String, Object?>{
        'msg': <String, Object?>{
          'turn_id': 'turn-1',
          'item': <String, Object?>{'id': 'answer-1', 'type': 'agentMessage'},
        },
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('codex/event/task_complete', <String, Object?>{
        'msg': <String, Object?>{
          'turn_id': 'turn-1',
          'last_agent_message': 'done',
        },
      }),
      now: now,
    );
    final answer = cells.singleWhere((cell) => cell.id == 'assistant-turn-1');
    expect(answer.kind, CodexTimelineKind.assistantMessage);
    expect(answer.markdownText, 'done');
    expect(answer.isStreaming, isFalse);
  });

  test('preserves commentary phase and de-duplicates repeated output', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _message('codex/event/item_started', <String, Object?>{
        'msg': <String, Object?>{
          'turn_id': 'turn-1',
          'item': <String, Object?>{
            'id': 'commentary-1',
            'type': 'AgentMessage',
            'phase': 'commentary',
          },
        },
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/agentMessage/delta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'commentary-1',
        'delta': 'Inspecting files',
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/commandExecution/outputDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'command-1',
        'delta': 'clean',
      }),
      now: now,
    );
    final repeated = CodexTimelineReducer.reduce(
      cells,
      _message('item/commandExecution/outputDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'command-1',
        'delta': 'clean',
      }),
      now: now,
    );
    expect(
      repeated.singleWhere((cell) => cell.itemId == 'commentary-1').kind,
      CodexTimelineKind.progressText,
    );
    expect(
      repeated.singleWhere((cell) => cell.itemId == 'command-1').detailsText,
      'clean',
    );
    expect(repeated, hasLength(cells.length));
  });

  test('replaces a legacy assistant provisional with its canonical item', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _message('item/agentMessage/delta', <String, Object?>{
        'turnId': 'turn-1',
        'delta': 'Complete answer',
      }),
      now: now,
    );
    expect(cells.single.id, 'assistant-turn-1');

    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/completed', <String, Object?>{
        'turnId': 'turn-1',
        'item': <String, Object?>{
          'id': 'answer-1',
          'type': 'agentMessage',
          'text': 'Complete answer',
        },
      }),
      now: now,
    );

    expect(cells, hasLength(1));
    expect(cells.single.id, 'item-answer-1');
    expect(cells.single.itemId, 'answer-1');
    expect(cells.single.markdownText, 'Complete answer');
    expect(cells.single.status, CodexTimelineStatus.completed);
  });

  test('parses structured questions and session approval actions', () {
    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'pendingRequests': <Object?>[
        <String, Object?>{
          'id': 7,
          'method': 'item/tool/request_user_input',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'mode',
                'header': 'Mode',
                'question': 'How should I proceed?',
                'options': <Object?>[
                  <String, Object?>{'label': 'Fast'},
                  <String, Object?>{'label': 'Careful'},
                ],
              },
            ],
          },
        },
        <String, Object?>{
          'id': 8,
          'method': 'item/commandExecution/requestApproval',
          'params': <String, Object?>{'command': 'git status'},
        },
      ],
    });
    expect(snapshot.pendingRequests[0].isQuestion, isTrue);
    expect(snapshot.pendingRequests[0].questions.single.options, hasLength(2));
    expect(snapshot.pendingRequests[1].isApproval, isTrue);
    expect(snapshot.pendingRequests[1].approvalDescription, 'git status');
  });

  test('restores legacy raw events into durable timeline cells', () {
    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'events': <Object?>[
        _message('item/agentMessage/delta', <String, Object?>{
          'turnId': 'turn-1',
          'itemId': 'answer-1',
          'delta': 'restored',
        }),
      ],
    });
    expect(snapshot.timelineCells.single.markdownText, 'restored');
    expect(snapshot.toJson()['timelineCells'], isA<List<Object?>>());
  });

  test(
    'model metadata preserves supported reasoning and fast-mode behavior',
    () {
      final model = CodexModelOption.fromJson(<String, Object?>{
        'id': 'gpt-current',
        'displayName': 'Current Codex',
        'isDefault': true,
        'contextWindowTokens': 128000,
        'supportsFastMode': true,
        'reasoningEfforts': <String>['medium', 'high'],
      });
      expect(model.isDefault, isTrue);
      expect(model.contextWindowTokens, 128000);
      expect(model.reasoningEfforts, <String>['medium', 'high']);
      expect(model.supportsFastMode, isTrue);
    },
  );

  test('shows only the latest actionable plan after the latest user turn', () {
    CodexChatSnapshot snapshot(Object? pendingRequests) =>
        CodexChatSnapshot.fromJson(<String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'old-user',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Old request',
            },
            <String, Object?>{
              'id': 'old-plan',
              'kind': 'plan',
              'status': 'completed',
              'markdownText': 'Old plan',
            },
            <String, Object?>{
              'id': 'latest-user',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Latest request',
            },
            <String, Object?>{
              'id': 'latest-plan',
              'kind': 'plan',
              'status': 'completed',
              'markdownText': 'Latest plan',
            },
          ],
          'pendingRequests': pendingRequests,
        });

    expect(snapshot(const <Object?>[]).shouldShowImplementPlan, isTrue);
    expect(
      snapshot(<Object?>[
        <String, Object?>{
          'id': 5,
          'method': 'item/tool/request_user_input',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'plan',
                'question': 'Implement this plan?',
              },
            ],
          },
        },
      ]).shouldShowImplementPlan,
      isFalse,
    );

    final reset = CodexChatSnapshot.fromJson(<String, Object?>{
      'timelineCells': <Object?>[
        <String, Object?>{
          'id': 'user',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Create a plan',
        },
        <String, Object?>{
          'id': 'plan',
          'kind': 'plan',
          'status': 'completed',
          'markdownText': 'Stale plan',
        },
        <String, Object?>{
          'id': 'boundary',
          'kind': 'systemNotice',
          'status': 'info',
          'metadata': <String, Object?>{'noticeType': 'threadBoundary'},
        },
      ],
    });
    expect(reset.latestActionablePlan, isNull);
  });

  test('preserves reasoning order and structured fast service tiers', () {
    final model = CodexModelOption.fromJson(<String, Object?>{
      'id': 'gpt-5.6-sol',
      'supportedReasoningEfforts': <Object?>[
        <String, Object?>{'reasoningEffort': 'xhigh'},
        <String, Object?>{'reasoningEffort': 'low'},
      ],
      'additionalSpeedTiers': <Object?>[
        <String, Object?>{'id': 'fast', 'displayName': 'Fast'},
      ],
      'serviceTiers': <Object?>[
        <String, Object?>{
          'id': 'priority',
          'options': <Object?>[
            <String, Object?>{'name': 'fast'},
          ],
        },
      ],
    });
    expect(model.reasoningEfforts, <String>['xhigh', 'low']);
    expect(model.supportsFastMode, isTrue);
  });
}
