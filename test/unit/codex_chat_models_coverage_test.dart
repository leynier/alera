import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

part 'codex_chat_snapshot_coverage_test_cases.dart';

void main() {
  final now = DateTime.utc(2026, 8, 3, 12);

  test('input attachments and draft items retain their values', () {
    const attachment = CodexInputAttachment(
      id: 'attachment-1',
      path: '/tmp/image.png',
      isImage: true,
      mimeType: 'image/png',
      displayName: 'image.png',
      sizeBytes: 42,
      detail: 'high',
    );
    const draftItem = CodexDraftItem(
      id: 'skill-1',
      kind: CodexDraftItemKind.skill,
      name: 'Review',
      path: '/skills/review',
      tokenText: r'$Review',
    );

    expect(attachment.path, '/tmp/image.png');
    expect(attachment.isImage, isTrue);
    expect(draftItem.kind, CodexDraftItemKind.skill);
    expect(draftItem.tokenText, r'$Review');
  });

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

  registerCodexSnapshotCoverageTests(now);
}
