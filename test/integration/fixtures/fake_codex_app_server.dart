import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  var initialized = false;
  var activeThreadId = 'thr_fake';
  var activeTurnId = 'turn_fake';
  String? interruptibleTurnId;

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

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
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
      _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'thread/started',
        'params': <String, dynamic>{
          'thread': <String, dynamic>{'id': activeThreadId},
        },
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

      if (prompt.contains('trigger_approval')) {
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
}

void _write(Map<String, dynamic> payload) {
  stdout.writeln(jsonEncode(payload));
}
