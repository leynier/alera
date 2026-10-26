import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatProviderSkill _skill(
  String name, {
  String? displayName,
  String? shortDescription,
  String? description,
  String? scope,
  bool enabled = true,
  bool userInvocable = true,
}) => AgentChatProviderSkill(
  name: name,
  path: '/skills/$name/SKILL.md',
  displayName: displayName,
  shortDescription: shortDescription,
  description: description,
  scope: scope,
  enabled: enabled,
  userInvocable: userInvocable,
);

void main() {
  group('AgentChatSkillList', () {
    test('parses the runtime answer and its status', () {
      final list = AgentChatSkillList.fromJson(<String, Object?>{
        'status': 'ready',
        'skills': <Object?>[
          <String, Object?>{
            'name': r'$review',
            'path': '/a/SKILL.md',
            'enabled': true,
            'displayName': 'Code Review',
            'shortDescription': 'Reviews',
            'scope': 'user',
            'userInvocationOnly': true,
          },
          <String, Object?>{'name': 'review', 'path': '/dup/SKILL.md'},
          <String, Object?>{'name': 'two words', 'path': '/x'},
          <String, Object?>{'name': 'nopath'},
          <String, Object?>{
            'name': 'agent-only',
            'path': '/b',
            'userInvocable': false,
          },
          <String, Object?>{'name': 'off', 'path': '/c', 'enabled': false},
        ],
      });
      expect(list.status, AgentChatSkillsStatus.ready);
      expect(list.skills.map((skill) => skill.name), <String>[
        'review',
        'agent-only',
        'off',
      ]);
      final review = list.skills.first;
      expect(review.label, 'Code Review');
      expect(review.detail, 'Reviews');
      expect(review.userInvocationOnly, isTrue);
      expect(review.insertion, r'$review ');
      expect(list.invocable.map((skill) => skill.name), <String>['review']);
      expect(
        AgentChatSkillList.fromJson(<String, Object?>{'status': 'pending'})
            .status,
        AgentChatSkillsStatus.pending,
      );
      final failed = AgentChatSkillList.fromJson(<String, Object?>{
        'status': 'failed',
        'error': 'Skill discovery timed out.',
      });
      expect(failed.status, AgentChatSkillsStatus.failed);
      expect(failed.error, 'Skill discovery timed out.');
    });

    test('labels and source kinds follow T3 Code', () {
      expect(_skill('plugin:deploy-app').label, 'Plugin Deploy App');
      expect(_skill('x', scope: 'repo').detail, 'repo skill');
      expect(_skill('x').detail, 'Run provider skill');
      expect(
        const AgentChatProviderSkill(
          name: 'x',
          path: '/home/me/.codex/plugins/p/skills/x/SKILL.md',
        ).sourceKind,
        AgentChatSkillSourceKind.app,
      );
      expect(
        _skill('x', scope: 'Workspace').sourceKind,
        AgentChatSkillSourceKind.project,
      );
      expect(
        _skill('x', scope: 'personal').sourceKind,
        AgentChatSkillSourceKind.personal,
      );
      expect(_skill('x').sourceKind, AgentChatSkillSourceKind.other);
    });
  });

  group('mentions', () {
    final skills = <AgentChatProviderSkill>[
      _skill('review'),
      _skill('plugin:deploy'),
    ];

    test('match known names with the shared grammar', () {
      final mentions = agentChatSkillMentions(
        r'€review then $plugin:deploy and $unknown or $5',
        skills,
      );
      expect(mentions.map((mention) => mention.skill.name), <String>[
        'review',
        'plugin:deploy',
      ]);
      expect(mentions.first.start, 0);
      expect(mentions.first.end, 7);
      expect(agentChatSkillMentions(r'x$review', skills), isEmpty);
      expect(agentChatSkillMentions(r'$review.', skills), isEmpty);
    });

    test('typing waits for the space after a name', () {
      expect(agentChatSkillMentions(r'$review', skills, typing: true), isEmpty);
      expect(
        agentChatSkillMentions(r'$review ', skills, typing: true),
        hasLength(1),
      );
    });

    test('segments split text around mentions', () {
      expect(agentChatSkillTextSegments(r'run $review now', skills), <Object>[
        const AgentChatSkillTextSegment(text: 'run '),
        AgentChatSkillTextSegment(text: r'$review', skill: skills.first),
        const AgentChatSkillTextSegment(text: ' now'),
      ]);
      expect(agentChatSkillTextSegments('plain', skills), <Object>[
        const AgentChatSkillTextSegment(text: 'plain'),
      ]);
    });
  });

  group('search', () {
    final skills = <AgentChatProviderSkill>[
      _skill('deploy', shortDescription: 'Ship the app'),
      _skill('review', displayName: 'Code Review'),
      _skill('code-style'),
      _skill('agent-only', userInvocable: false),
      _skill('off', enabled: false),
      _skill('REVIEW'),
    ];

    test('ranks like T3 Code and hides what a person cannot pick', () {
      expect(
        agentChatSearchProviderSkills(skills, '').map((skill) => skill.name),
        <String>['deploy', 'review', 'code-style'],
      );
      expect(
        agentChatSearchProviderSkills(
          skills,
          'code',
        ).map((skill) => skill.name),
        <String>['code-style', 'review'],
      );
      expect(
        agentChatSearchProviderSkills(skills, r'$dep').single.name,
        'deploy',
      );
      expect(
        agentChatSearchProviderSkills(skills, 'ship').single.name,
        'deploy',
      );
      expect(agentChatSearchProviderSkills(skills, 'zzz'), isEmpty);
    });
  });

  group('slash menu', () {
    List<String> names(
      AgentChatSlashCommandState state, {
      String query = '',
      bool atPromptStart = true,
    }) => <String>[
      for (final entry in agentChatSlashMenuEntries(
        state,
        query: query,
        atPromptStart: atPromptStart,
      ))
        entry.name,
    ];

    final state = AgentChatSlashCommandState(
      providerCommands: const <AgentChatProviderCommand>[
        AgentChatProviderCommand(name: 'compact'),
        AgentChatProviderCommand(name: 'review'),
      ],
      providerSkills: <AgentChatProviderSkill>[
        _skill('review'),
        _skill('hidden', userInvocable: false),
      ],
    );

    test('lists skills last and drops agent commands they shadow', () {
      expect(names(state), <String>[
        'model',
        'usage',
        'compact',
        'skill:review',
      ]);
    });

    test('agent commands only expand at the start of the prompt', () {
      expect(names(state, atPromptStart: false), <String>[
        'model',
        'usage',
        'skill:review',
      ]);
    });

    test('skill queries match skill, skill: and the skill itself', () {
      expect(names(state, query: 'skill'), <String>['skill:review']);
      expect(names(state, query: 'skill:rev'), <String>['skill:review']);
      expect(names(state, query: 'rev'), <String>['skill:review']);
      expect(names(state, query: 'ski'), <String>['skill:review']);
      expect(names(state, query: 'comp'), <String>['compact']);
    });

    test('the setting hides skills', () {
      expect(
        names(
          AgentChatSlashCommandState(
            providerCommands: state.providerCommands,
            providerSkills: state.providerSkills,
            showSkills: false,
          ),
        ),
        <String>['model', 'usage', 'compact', 'review'],
      );
    });
  });

  test('locale compare orders like the Rust adapters', () {
    final names = <String>['b', 'a:b', 'A', 'a', 'a-b', 'a_b', 'ab', '2spec']
      ..sort(agentChatLocaleCompare);
    expect(names, <String>['2spec', 'a', 'A', 'a_b', 'a-b', 'a:b', 'ab', 'b']);
  });

  group('loader', () {
    test(
      'keeps the list while it refreshes and reuses a fresh answer',
      () async {
        var now = DateTime(2026);
        final calls = <bool>[];
        var answer = const AgentChatSkillList(
          skills: <AgentChatProviderSkill>[
            AgentChatProviderSkill(name: 'a', path: '/a'),
          ],
        );
        final loader = AgentChatSkillsLoader(({required refresh}) async {
          calls.add(refresh);
          return answer;
        }, clock: () => now);
        var notified = 0;
        loader.addListener(() => notified++);
        final first = loader.request();
        expect(loader.loading, isTrue);
        await first;
        expect(loader.skills.single.name, 'a');
        await loader.request();
        expect(calls, <bool>[false], reason: 'a fresh answer is reused');
        now = now.add(agentChatSkillsFreshness);
        answer = const AgentChatSkillList(
          skills: <AgentChatProviderSkill>[
            AgentChatProviderSkill(name: 'b', path: '/b'),
          ],
        );
        final second = loader.request();
        expect(loader.skills.single.name, 'a', reason: 'kept while loading');
        await second;
        expect(loader.skills.single.name, 'b');
        await loader.refresh();
        expect(calls, <bool>[false, false, true]);
        expect(notified, greaterThanOrEqualTo(6));
        loader.reset();
        expect(loader.list, isNull);
      },
    );

    test(
      'an older runtime marks skills unsupported and stops asking',
      () async {
        var calls = 0;
        final loader = AgentChatSkillsLoader(({required refresh}) async {
          calls++;
          throw const AgentChatCapabilityRequired(
            AgentChatWire.skillsCapability,
          );
        });
        await loader.request();
        expect(loader.unsupported, isTrue);
        await loader.request();
        await loader.refresh();
        expect(calls, 1);
      },
    );

    test('a failure is reported and retried on the next request', () async {
      var fail = true;
      final loader = AgentChatSkillsLoader(({required refresh}) async {
        if (fail) throw StateError('offline');
        return AgentChatSkillList.empty;
      });
      await loader.request();
      expect(loader.error, isA<StateError>());
      fail = false;
      await loader.request();
      expect(loader.error, isNull);
      expect(loader.list, isNotNull);
    });
  });
}
