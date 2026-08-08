import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 3, 12);

  test('model parsing accepts every current compatibility shape', () {
    final model = CodexModelOption.fromJson(<String, Object?>{
      'model': 'gpt-nested',
      'name': 'Nested model',
      'default': true,
      'contextWindow': '64000',
      'reasoning': <Object?, Object?>{
        'efforts': <Object?>[
          <Object?, Object?>{'effort': ' high '},
          <Object?, Object?>{'id': 'low'},
          <Object?, Object?>{'name': 'medium'},
          'xhigh',
          '',
        ],
      },
      'defaultReasoningEffort': 'high',
      'serviceTier': <Object?, Object?>{
        'nested': <Object?>[
          <Object?, Object?>{'slug': 'fast'},
        ],
      },
    });

    expect(model.id, 'gpt-nested');
    expect(model.label, 'Nested model');
    expect(model.isDefault, isTrue);
    expect(model.contextWindowTokens, 64000);
    expect(model.reasoningEfforts, <String>['high', 'low', 'medium', 'xhigh']);
    expect(model.defaultReasoningEffort, 'high');
    expect(model.supportsFastMode, isTrue);

    expect(
      CodexModelOption.fromJson(<String, Object?>{
        'serviceTierOptions': <Object?>['fast'],
      }).supportsFastMode,
      isTrue,
    );
  });

  test('model labels use the compact Codex presentation names', () {
    expect(
      CodexModelOption.fromJson(<String, Object?>{
        'id': 'gpt-5.6-luna',
        'displayName': 'GPT-5.6-Luna',
      }).label,
      '5.6 Luna',
    );
    expect(
      CodexModelOption.fromJson(<String, Object?>{
        'id': 'gpt-5.3-codex-spark',
        'displayName': 'GPT-5.3-Codex-Spark',
      }).label,
      '5.3 Codex Spark',
    );
    expect(
      CodexModelOption.fromJson(<String, Object?>{
        'id': 'custom',
        'displayName': 'Custom Codex',
      }).label,
      'Custom Codex',
    );
  });

  test('thread summaries parse app-server Unix timestamps in seconds', () {
    final thread = CodexThreadSummary.fromJson(<String, Object?>{
      'id': 'thread-1',
      'preview': 'Inspect the repository',
      'createdAt': 1786190400,
      'updatedAt': 1786190460.5,
      'recencyAt': 1786190520,
    });

    expect(thread.createdAt, DateTime.utc(2026, 8, 8, 12));
    expect(thread.updatedAt, DateTime.utc(2026, 8, 8, 12, 1, 0, 500));
    expect(thread.recencyAt, DateTime.utc(2026, 8, 8, 12, 2));
  });

  test(
    'pending requests expose approval, question and elicitation contracts',
    () {
      CodexPendingRequest request(
        String method, [
        Map<String, Object?>? params,
      ]) => CodexPendingRequest.fromJson(<Object?, Object?>{
        'id': 1,
        'method': method,
        'params': params ?? const <String, Object?>{},
      });

      expect(request('item/permission/check').isApproval, isTrue);
      expect(request('item/requestCommand').isApproval, isTrue);
      expect(request('item/requestFile').isApproval, isTrue);
      expect(
        request('item/permissions/requestApproval').isPermissionsRequest,
        isTrue,
      );

      final elicitation = request(
        'mcpServer/elicitation/request',
        <String, Object?>{
          'isBlocking': false,
          'autoResolutionMs': '120000',
          'mode': 'openai/form',
          'requestedSchema': <Object?, Object?>{
            'properties': <String, Object?>{'name': <String, Object?>{}},
          },
        },
      );
      expect(elicitation.isElicitation, isTrue);
      expect(elicitation.isBlocking, isFalse);
      expect(elicitation.autoResolutionMs, 120000);
      expect(elicitation.elicitationMode, 'openai/form');
      expect(elicitation.elicitationSchema, contains('properties'));
      expect(elicitation.hasSupportedElicitationForm, isTrue);
      expect(elicitation.requestTitle, 'MCP Server Needs Input');

      expect(
        request('mcpServer/elicitation/request', <String, Object?>{
          'mode': 'openai/form',
          'requestedSchema': <String, Object?>{
            'properties': <String, Object?>{
              'image': <String, Object?>{'type': 'openai/imagePicker'},
            },
          },
        }).hasSupportedElicitationForm,
        isFalse,
      );
      expect(
        request('mcpServer/elicitation/request', <String, Object?>{
          'mode': 'form',
          'requestedSchema': <String, Object?>{
            'properties': <String, Object?>{
              'role': <String, Object?>{
                'type': 'string',
                'enum': <String>['admin', 'member'],
              },
            },
          },
        }).hasSupportedElicitationForm,
        isFalse,
      );

      expect(
        request('other', <String, Object?>{'autoResolutionMs': 1}).isBlocking,
        isFalse,
      );
      expect(request('other').isBlocking, isTrue);

      final question = request('other', <String, Object?>{
        'questions': <Object?>[
          <Object?, Object?>{
            'key': 'choice',
            'prompt': 'Choose one',
            'options': <Object?>[
              <Object?, Object?>{
                'value': 'First',
                'description': 'The first option',
              },
              2,
            ],
            'isOther': true,
            'isSecret': true,
            'multiSelect': true,
          },
        ],
      });
      expect(question.isQuestion, isTrue);
      expect(question.questions.single.id, 'choice');
      expect(question.questions.single.question, 'Choose one');
      expect(question.questions.single.options.last.label, '2');
      expect(question.questions.single.isOther, isTrue);
      expect(question.questions.single.isSecret, isTrue);
      expect(question.questions.single.isMultiSelect, isTrue);
      expect(question.requestTitle, 'Codex Needs Your Input');

      final fallback = request('other', <String, Object?>{'text': 'Fallback'});
      expect(fallback.questions.single.question, 'Fallback');
      expect(fallback.requestTitle, 'Codex Request');
    },
  );

  test('legacy timeline events classify every visible row type', () {
    CodexTimelineEvent event(String method, String type) =>
        CodexTimelineEvent.fromJson(<String, Object?>{
          'method': method,
          'params': <String, Object?>{
            'item': <String, Object?>{
              'type': type,
              'text': 'text',
              'name': 'name',
            },
          },
        });

    expect(event('item/agentMessage', 'agent').isAssistant, isTrue);
    expect(event('event', 'user').isUser, isTrue);
    expect(event('item/reasoning', 'event').isReasoning, isTrue);
    expect(event('item/tool', 'event').isTool, isTrue);
    expect(event('item/command', 'event').isCommand, isTrue);
    expect(event('item/diff', 'event').isDiff, isTrue);
    expect(event('item/plan', 'event').isPlan, isTrue);
    expect(event('item/collab', 'event').isSubAgent, isTrue);
    expect(event('item/subagent', 'event').isSubAgent, isTrue);
  });

  test('snapshots serialize requests and filter stale plan prompts', () {
    Map<String, Object?> cell(
      String id,
      String kind, {
      String status = 'completed',
      String markdown = 'text',
      bool streaming = false,
    }) => <String, Object?>{
      'id': id,
      'kind': kind,
      'status': status,
      'markdownText': markdown,
      'isStreaming': streaming,
    };

    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'timelineCells': <Object?>[
        cell('user', 'userMessage'),
        cell('failed', 'plan', status: 'failed'),
        cell('declined', 'plan', status: 'declined'),
        cell('streaming', 'plan', streaming: true),
        cell('empty', 'plan', markdown: ' '),
        cell('valid', 'plan', markdown: 'Implement this'),
        cell('latest-invalid', 'plan', status: 'failed'),
      ],
      'pendingRequests': <Object?>[
        <String, Object?>{
          'id': 9,
          'method': 'request',
          'params': <String, Object?>{'value': true},
        },
      ],
      'activeTurnId': 'turn-1',
      'contextUsed': 10,
      'contextLimit': 20,
      'title': 'Thread',
    });

    expect(snapshot.latestActionablePlan?.id, 'valid');
    expect(snapshot.hasPlan, isTrue);
    expect(snapshot.isBusy, isTrue);
    final json = snapshot.toJson();
    expect(json['pendingRequests'], hasLength(1));
    expect(json['activeTurnId'], 'turn-1');
    expect(json['contextUsed'], 10);
    expect(json['contextLimit'], 20);
    expect(json['title'], 'Thread');

    expect(const CodexChatSnapshot().latestActionablePlan, isNull);
    expect(const CodexChatSnapshot().hasPlan, isFalse);

    final progressOnly = CodexChatSnapshot.fromJson(<String, Object?>{
      'timelineCells': <Object?>[
        cell('user', 'userMessage'),
        <String, Object?>{
          ...cell('progress', 'plan', markdown: 'Execution progress'),
          'metadata': <String, Object?>{
            'plan': <Object?>[
              <String, Object?>{'step': 'Build', 'status': 'completed'},
            ],
          },
        },
      ],
    });
    expect(progressOnly.latestActionablePlan, isNull);
    expect(progressOnly.shouldShowImplementPlan, isFalse);
  });

  test('snapshot deltas preserve unchanged cells and derived history', () {
    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'timelineCells': <Object?>[
        <String, Object?>{
          'id': 'user',
          'kind': 'userMessage',
          'markdownText': 'First prompt',
        },
        <String, Object?>{
          'id': 'stable',
          'kind': 'assistantMessage',
          'markdownText': 'Stable response',
        },
        <String, Object?>{
          'id': 'stream',
          'kind': 'assistantMessage',
          'markdownText': 'One',
        },
      ],
      'pendingRequests': <Object?>[
        <String, Object?>{'id': 1, 'method': 'request'},
      ],
      'activeTurnId': 'turn-1',
    });
    final stable = snapshot.timelineCells[1];
    final pending = snapshot.pendingRequests;
    final history = snapshot.promptHistory;

    final updated = snapshot.applyDelta(<String, Object?>{
      'timelineUpserts': <Object?>[
        <String, Object?>{
          'id': 'stream',
          'kind': 'assistantMessage',
          'markdownText': 'One two',
        },
      ],
      'timelineRemovedIds': const <Object?>[],
      'eventsAppend': <Object?>[
        <String, Object?>{'method': 'item/agentMessage/delta'},
      ],
      'eventLimit': 160,
      'activeTurnId': null,
      'contextUsed': 42,
    });

    expect(identical(updated.timelineCells[1], stable), isTrue);
    expect(updated.timelineCells[2].markdownText, 'One two');
    expect(identical(updated.pendingRequests, pending), isTrue);
    expect(identical(updated.promptHistory, history), isTrue);
    expect(updated.activeTurnId, isNull);
    expect(updated.contextUsed, 42);
    expect(updated.events, hasLength(1));

    final withSecondPrompt = updated.applyDelta(<String, Object?>{
      'timelineUpserts': <Object?>[
        <String, Object?>{
          'id': 'user-2',
          'kind': 'userMessage',
          'markdownText': 'Second prompt',
        },
      ],
    });
    expect(withSecondPrompt.promptHistory, <String>[
      'First prompt',
      'Second prompt',
    ]);
  });

  test('snapshot deltas share expanded history while updating live cells', () {
    CodexTimelineCell cell(String id, String text) =>
        CodexTimelineCell.fromJson(<String, Object?>{
          'id': id,
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': text,
        });
    final timeline = CodexTimelineCells.segmented(
      history: <CodexTimelineCell>[
        for (var index = 0; index < 1000; index++)
          cell('history-$index', 'History $index'),
      ],
      live: <CodexTimelineCell>[cell('live', 'One')],
    );
    final snapshot = CodexChatSnapshot(timelineCells: timeline);

    final updated = snapshot.applyDelta(<String, Object?>{
      'timelineUpserts': <Object?>[
        <String, Object?>{
          'id': 'live',
          'kind': 'assistantMessage',
          'status': 'inProgress',
          'isStreaming': true,
          'markdownText': 'One two',
        },
      ],
    });

    final updatedTimeline = updated.timelineCells as CodexTimelineCells;
    expect(identical(updatedTimeline.history, timeline.history), isTrue);
    expect(updatedTimeline.length, 1001);
    expect(updatedTimeline.last.markdownText, 'One two');
  });

  test('snapshot deltas replace raw events after host byte eviction', () {
    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'events': <Object?>[
        <String, Object?>{'method': 'old'},
      ],
    });

    final next = snapshot.applyDelta(<String, Object?>{
      'eventsAppend': <Object?>[
        <String, Object?>{'method': 'large'},
      ],
      'eventsReplace': <Object?>[
        <String, Object?>{'method': 'retained'},
      ],
    });

    expect(next.events, hasLength(1));
    expect(next.events.single.method, 'retained');
  });

  test('snapshot tracks MCP initialization across timeline deltas', () {
    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'timelineCells': <Object?>[
        <String, Object?>{
          'id': 'mcp-startup-filesystem',
          'kind': 'toolCall',
          'status': 'inProgress',
          'isStreaming': true,
          'metadata': <String, Object?>{'itemType': 'mcpServerStartup'},
        },
      ],
    });
    expect(snapshot.mcpInitializing, isTrue);

    final ready = snapshot.applyDelta(<String, Object?>{
      'timelineUpserts': <Object?>[
        <String, Object?>{
          'id': 'mcp-startup-filesystem',
          'kind': 'toolCall',
          'status': 'completed',
          'isStreaming': false,
          'metadata': <String, Object?>{
            'itemType': 'mcpServerStartup',
            'status': 'ready',
          },
        },
      ],
    });
    expect(ready.mcpInitializing, isFalse);
  });

  test('recognizes plan questions and separates recommended option labels', () {
    final request = CodexPendingRequest.fromJson(<String, Object?>{
      'id': 9,
      'method': 'item/tool/request_user_input',
      'params': <String, Object?>{
        'questions': <Object?>[
          <String, Object?>{
            'id': 'implement',
            'question': 'Implement this plan?',
            'options': <Object?>[
              <String, Object?>{'label': 'Yes (Recommended)'},
            ],
          },
        ],
      },
    });

    expect(request.isImplementPlanQuestion, isTrue);
    expect(request.questions.single.options.single.isRecommended, isTrue);
    expect(request.questions.single.options.single.displayLabel, 'Yes');
  });

  test('Codex settings and tab payload getters round-trip typed values', () {
    final settings = CodexChatSettings.fromJson(<String, Object?>{
      'selectedModel': 'gpt-current',
      'reasoningEffort': 'high',
      'speedMode': 'fast',
      'permissionMode': 'never',
      'planMode': true,
    });
    expect(settings.selectedModel, 'gpt-current');
    expect(settings.planMode, isTrue);

    final tab = WorkspaceTabRecord(
      id: 'codex-tab',
      workspaceId: 'workspace',
      kind: WorkspaceTabKind.codex,
      title: 'Codex',
      createdAt: now,
      updatedAt: now,
      payload: <String, Object?>{
        workspaceTabCodexThreadIdPayloadKey: 'thread-1',
        workspaceTabCodexActiveTurnIdPayloadKey: 'turn-1',
        workspaceTabCodexSnapshotPayloadKey: <Object?, Object?>{
          'title': 'Chat',
        },
      },
    );
    expect(tab.codexThreadId, 'thread-1');
    expect(tab.codexActiveTurnId, 'turn-1');
    expect(tab.codexSnapshot, <String, Object?>{'title': 'Chat'});

    final empty = WorkspaceTabRecord(
      id: 'empty',
      workspaceId: 'workspace',
      kind: WorkspaceTabKind.codex,
      title: 'Codex',
      createdAt: now,
      updatedAt: now,
    );
    expect(empty.codexThreadId, isNull);
    expect(empty.codexActiveTurnId, isNull);
    expect(empty.codexSnapshot, isEmpty);
  });
}
