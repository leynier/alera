import 'dart:convert';
import 'dart:io';

WebSocket? _activeSocket;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  stderr.writeln('ws://127.0.0.1:${server.port}');

  var initialized = false;
  var activeThreadId = 'thr_fake';
  var activeTurnId = 'turn_fake';
  String? interruptibleTurnId;
  var detachedReviewCounter = 0;
  final Map<String, String> threadNames = <String, String>{};
  const allApps = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'demo-app',
      'name': 'Demo App',
      'description': 'Example connector for documentation.',
      'logoUrl': 'https://example.com/demo-app.png',
      'logoUrlDark': null,
      'distributionChannel': null,
      'branding': null,
      'appMetadata': null,
      'labels': <String, dynamic>{'tier': 'stable'},
      'installUrl': 'https://chatgpt.com/apps/demo-app/demo-app',
      'isAccessible': true,
      'isEnabled': true,
      'pluginDisplayNames': <String>['Demo Plugin'],
    },
    <String, dynamic>{
      'id': 'docs-app',
      'name': 'Docs App',
      'description': 'Indexes project docs.',
      'logoUrl': 'https://example.com/docs-app.png',
      'logoUrlDark': null,
      'distributionChannel': 'directory',
      'branding': null,
      'appMetadata': null,
      'labels': <String, dynamic>{'tier': 'beta'},
      'installUrl': 'https://chatgpt.com/apps/demo-app/docs-app',
      'isAccessible': false,
      'isEnabled': true,
      'pluginDisplayNames': <String>['Docs Plugin'],
    },
  ];

  void emitThreadStarted(String threadId) {
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'thread/started',
      'params': <String, dynamic>{
        'thread': <String, dynamic>{
          'id': threadId,
          ...?threadNames[threadId] == null
              ? null
              : <String, dynamic>{'title': threadNames[threadId]},
        },
      },
    });
  }

  void emitCompletedTurn({
    required String status,
    String itemStatus = 'completed',
  }) {
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/completed',
      'params': <String, dynamic>{
        'item': <String, dynamic>{
          'id': 'item_cmd_1',
          'type': 'commandExecution',
          'command': 'git status',
          'cwd': '.',
          'status': itemStatus,
          'aggregatedOutput': status == 'completed' ? 'ok' : '',
        },
      },
    });

    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'turn/completed',
      'params': <String, dynamic>{
        'turn': <String, dynamic>{
          'id': activeTurnId,
          'threadId': activeThreadId,
          'status': status,
          'items': <Object>[],
          'error': null,
        },
      },
    });
  }

  void emitReviewCompletedTurn({
    required String threadId,
    required String turnId,
    required String reviewLabel,
  }) {
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'turn/started',
      'params': <String, dynamic>{
        'turn': <String, dynamic>{
          'id': turnId,
          'threadId': threadId,
          'status': 'inProgress',
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/started',
      'params': <String, dynamic>{
        'threadId': threadId,
        'turnId': turnId,
        'item': <String, dynamic>{
          'type': 'enteredReviewMode',
          'id': '${turnId}_entered_review',
          'review': reviewLabel,
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/completed',
      'params': <String, dynamic>{
        'threadId': threadId,
        'turnId': turnId,
        'item': <String, dynamic>{
          'type': 'exitedReviewMode',
          'id': '${turnId}_exited_review',
          'status': 'completed',
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'turn/completed',
      'params': <String, dynamic>{
        'turn': <String, dynamic>{
          'id': turnId,
          'threadId': threadId,
          'status': 'completed',
          'items': <Object>[],
          'error': null,
        },
      },
    });
  }

  String reviewLabelForTarget(Map<String, dynamic> target) {
    switch (target['type']) {
      case 'uncommittedChanges':
        return 'current changes';
      case 'baseBranch':
        return 'base branch ${target['branch']}';
      case 'commit':
        return 'commit ${(target['sha'] ?? '').toString()}';
      case 'custom':
        return 'custom instructions';
    }
    return 'current changes';
  }

  List<Map<String, dynamic>> buildSkillsForCwd(
    String cwd,
    List<String> extraUserRoots,
  ) {
    final lastSegment =
        cwd.split('/').where((segment) => segment.isNotEmpty).isEmpty
        ? 'workspace'
        : cwd.split('/').where((segment) => segment.isNotEmpty).last;
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'name': '$lastSegment-skill',
        'description': 'Fake skill for $cwd',
        'shortDescription': 'Fake skill for tests',
        'path': '$cwd/.codex/skills/$lastSegment/SKILL.md',
        'scope': 'repo',
        'enabled': true,
        'interface': <String, dynamic>{
          'displayName': 'Fake $lastSegment skill',
          'shortDescription': 'Fake skill for tests',
          'defaultPrompt': 'Inspect $cwd',
        },
      },
      for (final extraRoot in extraUserRoots)
        <String, dynamic>{
          'name': '$lastSegment-extra-skill',
          'description': 'Extra fake skill for $extraRoot',
          'path': '$extraRoot/SKILL.md',
          'scope': 'user',
          'enabled': true,
        },
    ];
  }

  void emitCommentaryAndFinalTurn() {
    const commentaryItemId = 'msg_commentary_1';
    const finalItemId = 'msg_final_1';

    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'codex/event/item_started',
      'params': <String, dynamic>{
        'msg': <String, dynamic>{
          'type': 'item_started',
          'thread_id': activeThreadId,
          'turn_id': activeTurnId,
          'item': <String, dynamic>{
            'type': 'AgentMessage',
            'id': commentaryItemId,
            'phase': 'commentary',
          },
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/started',
      'params': <String, dynamic>{
        'threadId': activeThreadId,
        'turnId': activeTurnId,
        'item': <String, dynamic>{
          'type': 'agentMessage',
          'id': commentaryItemId,
          'text': '',
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/agentMessage/delta',
      'params': <String, dynamic>{
        'threadId': activeThreadId,
        'turnId': activeTurnId,
        'itemId': commentaryItemId,
        'delta': 'Voy a revisar el README\\n',
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'codex/event/item_completed',
      'params': <String, dynamic>{
        'msg': <String, dynamic>{
          'type': 'item_completed',
          'thread_id': activeThreadId,
          'turn_id': activeTurnId,
          'item': <String, dynamic>{
            'type': 'AgentMessage',
            'id': commentaryItemId,
            'phase': 'commentary',
            'content': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'Text',
                'text': 'Voy a revisar el README',
              },
            ],
          },
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/completed',
      'params': <String, dynamic>{
        'threadId': activeThreadId,
        'turnId': activeTurnId,
        'item': <String, dynamic>{
          'type': 'agentMessage',
          'id': commentaryItemId,
          'status': 'completed',
          'text': 'Voy a revisar el README',
        },
      },
    });

    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'codex/event/item_started',
      'params': <String, dynamic>{
        'msg': <String, dynamic>{
          'type': 'item_started',
          'thread_id': activeThreadId,
          'turn_id': activeTurnId,
          'item': <String, dynamic>{
            'type': 'AgentMessage',
            'id': finalItemId,
            'phase': 'final_answer',
          },
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/started',
      'params': <String, dynamic>{
        'threadId': activeThreadId,
        'turnId': activeTurnId,
        'item': <String, dynamic>{
          'type': 'agentMessage',
          'id': finalItemId,
          'text': '',
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/agentMessage/delta',
      'params': <String, dynamic>{
        'threadId': activeThreadId,
        'turnId': activeTurnId,
        'itemId': finalItemId,
        'delta': 'El readme.md esta en espanol.\\n',
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'codex/event/item_completed',
      'params': <String, dynamic>{
        'msg': <String, dynamic>{
          'type': 'item_completed',
          'thread_id': activeThreadId,
          'turn_id': activeTurnId,
          'item': <String, dynamic>{
            'type': 'AgentMessage',
            'id': finalItemId,
            'phase': 'final_answer',
            'content': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'Text',
                'text': 'El readme.md esta en espanol.',
              },
            ],
          },
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/completed',
      'params': <String, dynamic>{
        'threadId': activeThreadId,
        'turnId': activeTurnId,
        'item': <String, dynamic>{
          'type': 'agentMessage',
          'id': finalItemId,
          'status': 'completed',
          'text': 'El readme.md esta en espanol.',
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'codex/event/task_complete',
      'params': <String, dynamic>{
        'msg': <String, dynamic>{
          'type': 'task_complete',
          'turn_id': activeTurnId,
          'last_agent_message': 'El readme.md esta en espanol.',
        },
      },
    });
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'turn/completed',
      'params': <String, dynamic>{
        'turn': <String, dynamic>{
          'id': activeTurnId,
          'threadId': activeThreadId,
          'status': 'completed',
          'items': <Object>[],
          'error': null,
        },
      },
    });
  }

  await for (final request in server) {
    final socket = await WebSocketTransformer.upgrade(request);
    _activeSocket = socket;

    await for (final rawLine in socket) {
      final line = rawLine.toString();
      if (line.trim().isEmpty) {
        continue;
      }

      final message = jsonDecode(line) as Map<String, dynamic>;
      final method = message['method'] as String?;
      final id = message['id'];

      if (method == 'initialize') {
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{
            'serverInfo': <String, dynamic>{
              'name': 'fake-codex-app-server',
              'version': '0.1.0',
            },
          },
        });
        continue;
      }

      if (method == 'initialized') {
        initialized = true;
        continue;
      }

      if (!initialized) {
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32002,
            'message': 'Not initialized',
          },
        });
        continue;
      }

      if (method == 'thread/start') {
        final params =
            (message['params'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .cast<String, dynamic>();
        if (params['approvalPolicy'] != 'never') {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': id,
            'error': <String, dynamic>{
              'code': -32010,
              'message': 'thread/start expected approvalPolicy=never',
            },
          });
          continue;
        }

        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{
            'thread': <String, dynamic>{
              'id': activeThreadId,
              'preview': '',
              'modelProvider': 'openai',
              'createdAt': 1730910000,
            },
          },
        });
        emitThreadStarted(activeThreadId);
        continue;
      }

      if (method == 'thread/name/set') {
        final params = (message['params'] as Map<String, dynamic>)
            .cast<String, dynamic>();
        final threadId = (params['threadId'] ?? '').toString();
        final name = (params['name'] ?? '').toString();
        threadNames[threadId] = name;
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{},
        });
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'thread/name/updated',
          'params': <String, dynamic>{'threadId': threadId, 'threadName': name},
        });
        continue;
      }

      if (method == 'turn/start') {
        final params = (message['params'] as Map<String, dynamic>)
            .cast<String, dynamic>();

        if (params.containsKey('collaborationMode')) {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': id,
            'error': <String, dynamic>{
              'code': -32011,
              'message': 'turn/start must not include collaborationMode',
            },
          });
          continue;
        }

        if (params['approvalPolicy'] != 'never') {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': id,
            'error': <String, dynamic>{
              'code': -32012,
              'message': 'turn/start expected approvalPolicy=never',
            },
          });
          continue;
        }

        final model = (params['model'] ?? '').toString();
        final reasoning =
            (params['reasoning'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .cast<String, dynamic>();
        final reasoningEffort = (reasoning['effort'] ?? '').toString();
        const allEfforts = <String>{'low', 'medium', 'high', 'xhigh'};
        if (!allEfforts.contains(reasoningEffort)) {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': id,
            'error': <String, dynamic>{
              'code': -32013,
              'message':
                  'turn/start expected valid reasoning.effort in low|medium|high|xhigh',
            },
          });
          continue;
        }
        if (model == 'gpt-5.1-codex-mini' &&
            reasoningEffort != 'medium' &&
            reasoningEffort != 'high') {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': id,
            'error': <String, dynamic>{
              'code': -32014,
              'message':
                  "Unsupported value: '$reasoningEffort' is not supported with the 'gpt-5.1-codex-mini' model.",
            },
          });
          continue;
        }
        final serviceTier = params['serviceTier']?.toString();
        if (serviceTier != null && serviceTier != 'fast') {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': id,
            'error': <String, dynamic>{
              'code': -32015,
              'message': 'turn/start expected serviceTier=null|fast',
            },
          });
          continue;
        }

        activeThreadId = (params['threadId'] ?? activeThreadId).toString();
        activeTurnId = 'turn_${DateTime.now().millisecondsSinceEpoch}';

        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{
            'turn': <String, dynamic>{
              'id': activeTurnId,
              'threadId': activeThreadId,
              'status': 'inProgress',
              'items': <Object>[],
            },
          },
        });

        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'turn/started',
          'params': <String, dynamic>{
            'turn': <String, dynamic>{
              'id': activeTurnId,
              'threadId': activeThreadId,
              'status': 'inProgress',
            },
          },
        });

        final input = (params['input'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<dynamic, dynamic>>();
        final prompt = input.isEmpty
            ? ''
            : (input.first['text'] ?? '').toString().toLowerCase();

        if (prompt.contains('trigger_service_tier_fast') &&
            serviceTier != 'fast') {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'turn/completed',
            'params': <String, dynamic>{
              'turn': <String, dynamic>{
                'id': activeTurnId,
                'threadId': activeThreadId,
                'status': 'failed',
                'items': <Object>[],
                'error': <String, dynamic>{
                  'message': 'expected serviceTier fast',
                },
              },
            },
          });
        } else if (prompt.contains('trigger_service_tier_normal') &&
            (!params.containsKey('serviceTier') || serviceTier != null)) {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'turn/completed',
            'params': <String, dynamic>{
              'turn': <String, dynamic>{
                'id': activeTurnId,
                'threadId': activeThreadId,
                'status': 'failed',
                'items': <Object>[],
                'error': <String, dynamic>{
                  'message': 'expected explicit serviceTier null',
                },
              },
            },
          });
        } else if (prompt.contains('trigger_approval')) {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': 900,
            'method': 'item/commandExecution/requestApproval',
            'params': <String, dynamic>{
              'threadId': activeThreadId,
              'turnId': activeTurnId,
              'itemId': 'item_cmd_1',
              'reason': 'needs approval',
              'command': 'git status',
              'cwd': params['cwd'] ?? '.',
              'commandActions': <String>['filesystemRead', 'processExecution'],
            },
          });
        } else if (prompt.contains('trigger_user_input_no_thread')) {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': 901,
            'method': 'item/tool/request_user_input',
            'params': <String, dynamic>{
              'turnId': activeTurnId,
              'itemId': 'item_user_input_1',
              'questions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'implement_now',
                  'header': 'Implementation',
                  'question': 'Implement this plan now?',
                  'isOther': false,
                  'isSecret': false,
                  'options': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'label': 'Yes, implement this plan',
                      'description': 'Proceed with implementation',
                    },
                    <String, dynamic>{
                      'label': 'No, change the plan',
                      'description': 'Keep refining the plan',
                    },
                  ],
                },
              ],
            },
          });
        } else if (prompt.contains('trigger_user_input_empty_thread')) {
          _write(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': 902,
            'method': 'item/tool/requestUserInput',
            'params': <String, dynamic>{
              'threadId': '   ',
              'turnId': activeTurnId,
              'itemId': 'item_user_input_2',
              'questions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'implement_now',
                  'header': 'Implementation',
                  'question': 'Implement this plan now?',
                  'isOther': false,
                  'isSecret': false,
                  'options': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'label': 'Yes, implement this plan',
                      'description': 'Proceed with implementation',
                    },
                  ],
                },
              ],
            },
          });
        } else if (prompt.contains('trigger_interrupt')) {
          interruptibleTurnId = activeTurnId;
        } else if (prompt.contains('trigger_commentary_final')) {
          emitCommentaryAndFinalTurn();
        } else if (prompt.contains('trigger_reasoning_medium')) {
          if (reasoningEffort != 'medium') {
            _write(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'turn/completed',
              'params': <String, dynamic>{
                'turn': <String, dynamic>{
                  'id': activeTurnId,
                  'threadId': activeThreadId,
                  'status': 'failed',
                  'items': <Object>[],
                  'error': <String, dynamic>{
                    'message': 'expected reasoning effort medium',
                  },
                },
              },
            });
          } else {
            emitCompletedTurn(status: 'completed');
          }
        } else {
          emitCompletedTurn(status: 'completed');
        }
        continue;
      }

      if (method == 'review/start') {
        final params = (message['params'] as Map<String, dynamic>)
            .cast<String, dynamic>();
        final parentThreadId = (params['threadId'] ?? activeThreadId)
            .toString();
        final delivery = (params['delivery'] ?? 'inline').toString();
        final target =
            (params['target'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .cast<String, dynamic>();
        final reviewThreadId = delivery == 'detached'
            ? 'thr_review_${++detachedReviewCounter}'
            : parentThreadId;
        final reviewTurnId =
            'review_turn_${DateTime.now().millisecondsSinceEpoch}';
        final reviewLabel = reviewLabelForTarget(target);

        if (delivery == 'detached') {
          activeThreadId = reviewThreadId;
          emitThreadStarted(reviewThreadId);
        }
        activeThreadId = reviewThreadId;
        activeTurnId = reviewTurnId;

        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{
            'turn': <String, dynamic>{
              'id': reviewTurnId,
              'status': 'inProgress',
              'items': <Object>[],
              'error': null,
            },
            'reviewThreadId': reviewThreadId,
          },
        });

        emitReviewCompletedTurn(
          threadId: reviewThreadId,
          turnId: reviewTurnId,
          reviewLabel: reviewLabel,
        );
        continue;
      }

      if (method == 'collaborationMode/list') {
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{
            'data': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'default',
                'mode': 'default',
                'model': 'gpt-5.2-codex',
                'reasoning_effort': null,
              },
              <String, dynamic>{
                'name': 'planner',
                'mode': 'plan',
                'model': 'gpt-5.2-codex',
                'reasoning_effort': 'high',
              },
            ],
          },
        });
        continue;
      }

      if (method == 'skills/list') {
        final params =
            (message['params'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .cast<String, dynamic>();
        final rawCwds = params['cwds'];
        final cwds = rawCwds is List && rawCwds.isNotEmpty
            ? rawCwds.map((cwd) => cwd.toString()).toList(growable: false)
            : <String>['/tmp/project'];
        final extraRootsByCwd = <String, List<String>>{};
        final rawExtraRoots = params['perCwdExtraUserRoots'];
        if (rawExtraRoots is List) {
          for (final entry in rawExtraRoots.whereType<Map>()) {
            final json = entry.cast<String, dynamic>();
            final cwd = json['cwd']?.toString();
            if (cwd == null || cwd.isEmpty) {
              continue;
            }
            final roots =
                (json['extraUserRoots'] as List<dynamic>? ?? const <dynamic>[])
                    .map((root) => root.toString())
                    .toList(growable: false);
            extraRootsByCwd[cwd] = roots;
          }
        }
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{
            'data': cwds
                .map(
                  (cwd) => <String, dynamic>{
                    'cwd': cwd,
                    'skills': buildSkillsForCwd(
                      cwd,
                      extraRootsByCwd[cwd] ?? const <String>[],
                    ),
                    'errors': <Object>[],
                  },
                )
                .toList(growable: false),
          },
        });
        continue;
      }

      if (method == 'app/list') {
        final params =
            (message['params'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .cast<String, dynamic>();
        final startIndex =
            int.tryParse((params['cursor'] ?? '0').toString()) ?? 0;
        final limit = params['limit'] is int
            ? params['limit'] as int
            : allApps.length;
        final nextIndex = startIndex + limit;
        final requestedThreadId = params['threadId']?.toString();
        final page = allApps
            .skip(startIndex)
            .take(limit)
            .map((app) {
              final copy = Map<String, dynamic>.from(app);
              if (requestedThreadId != null && requestedThreadId.isNotEmpty) {
                copy['labels'] = <String, dynamic>{
                  ...(copy['labels'] as Map<String, dynamic>? ??
                      const <String, dynamic>{}),
                  'threadId': requestedThreadId,
                };
              }
              return copy;
            })
            .toList(growable: false);
        final nextCursor = nextIndex < allApps.length ? '$nextIndex' : null;
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'app/list/updated',
          'params': <String, dynamic>{'data': page, 'nextCursor': nextCursor},
        });
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{'data': page, 'nextCursor': nextCursor},
        });
        continue;
      }

      if (id == 900 && message.containsKey('result')) {
        final result = message['result'] as Map<String, dynamic>;
        final decision = (result['decision'] ?? '').toString();
        if (decision == 'accept') {
          emitCompletedTurn(status: 'completed');
        } else {
          emitCompletedTurn(status: 'interrupted', itemStatus: 'declined');
        }
        continue;
      }

      if ((id == 901 || id == 902) && message.containsKey('result')) {
        emitCompletedTurn(status: 'completed');
        continue;
      }

      if (method == 'thread/resume') {
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{
            'thread': <String, dynamic>{
              'id': (message['params'] as Map<String, dynamic>)['threadId'],
              'preview': '',
              'modelProvider': 'openai',
              'createdAt': 1730910000,
            },
          },
        });
        continue;
      }

      if (method == 'turn/interrupt') {
        final params =
            (message['params'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .cast<String, dynamic>();
        final turnId = (params['turnId'] ?? '').toString();
        final threadId = (params['threadId'] ?? '').toString();
        if (interruptibleTurnId == turnId && activeThreadId == threadId) {
          interruptibleTurnId = null;
          emitCompletedTurn(status: 'interrupted', itemStatus: 'declined');
        }
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{},
        });
        continue;
      }

      _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{},
      });
    }

    await socket.close();
    _activeSocket = null;
    break;
  }

  await server.close(force: true);
}

void _write(Map<String, dynamic> payload) {
  final json = jsonEncode(payload);
  final socket = _activeSocket;
  if (socket != null) {
    socket.add(json);
    return;
  }
  stdout.writeln(json);
}
