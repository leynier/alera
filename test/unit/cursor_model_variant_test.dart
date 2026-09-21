import 'package:alera/src/features/agent_profiles/domain/cursor_model_catalog.dart';
import 'package:alera/src/features/agent_profiles/domain/cursor_model_variant.dart';
import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCursorModelSlug', () {
    test('splits published slug shapes from the right', () {
      _expectSlug('grok-4.7-xhigh', family: 'grok-4.7', effort: 'xhigh');
      _expectSlug(
        'grok-4.7-xhigh-fast',
        family: 'grok-4.7',
        effort: 'xhigh',
        fast: true,
      );
      _expectSlug(
        'claude-fable-5-1-high',
        family: 'claude-fable-5-1',
        effort: 'high',
      );
      _expectSlug(
        'claude-fable-5-1-thinking-high',
        family: 'claude-fable-5-1',
        effort: 'high',
        thinking: true,
      );
      _expectSlug(
        'claude-opus-4-8-thinking-high-fast',
        family: 'claude-opus-4-8',
        effort: 'high',
        thinking: true,
        fast: true,
      );
      _expectSlug('composer-2.5', family: 'composer-2.5');
      _expectSlug('composer-2.5-fast', family: 'composer-2.5', fast: true);
      _expectSlug(
        'claude-4.6-opus-high-thinking',
        family: 'claude-4.6-opus',
        effort: 'high',
        thinking: true,
      );
      _expectSlug(
        'claude-4.5-sonnet-thinking',
        family: 'claude-4.5-sonnet',
        thinking: true,
      );
      _expectSlug(
        'gpt-5.5-extra-high-fast',
        family: 'gpt-5.5',
        effort: 'extra-high',
        fast: true,
      );
      _expectSlug('kimi-k2.7-code', family: 'kimi-k2.7-code');
      _expectSlug('auto', family: 'auto');
    });

    test('keeps extra-high as one token', () {
      _expectSlug(
        'gpt-5.5-extra-high',
        family: 'gpt-5.5',
        effort: 'extra-high',
      );
    });

    test('rejects an empty slug and a suffix with no family', () {
      expect(parseCursorModelSlug(''), isNull);
      expect(parseCursorModelSlug('   '), isNull);
      expect(parseCursorModelSlug('-fast'), isNull);
      expect(parseCursorModelSlug('-thinking'), isNull);
    });

    test('does not read a bracket override as fast or thinking', () {
      final parsed = parseCursorModelSlug('grok-4.7[effort=xhigh,fast=true]');
      expect(parsed, isNotNull);
      expect(parsed!.effort, isNull);
      expect(parsed.thinking, isFalse);
      expect(parsed.fast, isFalse);
      expect(parsed.family, 'grok-4.7[effort=xhigh,fast=true]');
    });
  });

  group('CursorModelCatalog', () {
    final catalog = CursorModelCatalog.fromOptions(_exampleModels);

    test('groups discovered ids by family and keeps published labels', () {
      expect(catalog.families.map((family) => family.id).toList(), <String>[
        'grok-4.7',
        'claude-fable-5-1',
        'claude-opus-4-8',
        'composer-2.5',
        'claude-4.6-opus',
        'claude-4.5-sonnet',
        'gpt-5.5',
        'gpt-5.4',
        'kimi-k2.7-code',
        'auto',
        'claude-sonnet-5',
      ]);
      expect(catalog.familyById('grok-4.7')!.label, 'Grok 4.7');
      expect(catalog.familyById('claude-fable-5-1')!.label, 'Claude Fable 5.1');
      expect(catalog.familyById('claude-opus-4-8')!.label, 'Claude Opus 4.8');
      expect(catalog.familyById('composer-2.5')!.label, 'Composer 2.5');
      expect(catalog.familyById('claude-4.6-opus')!.label, 'Claude 4.6 Opus');
      expect(
        catalog.familyById('claude-4.5-sonnet')!.label,
        'Claude 4.5 Sonnet',
      );
      expect(catalog.familyById('gpt-5.5')!.label, 'GPT 5.5');
      expect(catalog.familyById('kimi-k2.7-code')!.label, 'Kimi K2.7 Code');
      expect(catalog.familyById('auto')!.label, 'Auto');
    });

    test(
      'lists only the efforts, thinking, and fast that a family publishes',
      () {
        final grok = catalog.familyById('grok-4.7')!;
        expect(grok.efforts, <String>['xhigh']);
        expect(grok.hasThinking, isFalse);
        expect(grok.hasFast, isTrue);

        final fable = catalog.familyById('claude-fable-5-1')!;
        expect(fable.efforts, <String>['high']);
        expect(fable.hasThinking, isTrue);
        expect(fable.hasFast, isFalse);
        expect(
          fable.canToggleFast(
            catalog.variantForModel('claude-fable-5-1-high')!,
          ),
          isFalse,
        );

        final composer = catalog.familyById('composer-2.5')!;
        expect(composer.efforts, isEmpty);
        expect(composer.hasThinking, isFalse);
        expect(composer.hasFast, isTrue);

        expect(catalog.familyById('auto')!.efforts, isEmpty);
        expect(catalog.familyById('auto')!.hasThinking, isFalse);
        expect(catalog.familyById('auto')!.hasFast, isFalse);
        expect(catalog.familyById('kimi-k2.7-code')!.efforts, isEmpty);
      },
    );

    test('round-trips a stored slug and hides an id outside the catalog', () {
      expect(catalog.variantForModel('grok-4.7-xhigh')!.id, 'grok-4.7-xhigh');
      expect(
        catalog.variantForModel('claude-fable-5-1-high')!.id,
        'claude-fable-5-1-high',
      );
      expect(
        catalog.slugForFamily(
          'grok-4.7',
          previous: catalog.variantForModel('grok-4.7-xhigh'),
        ),
        'grok-4.7-xhigh',
      );
      expect(catalog.variantForModel('not-a-real-model'), isNull);
      expect(
        catalog.variantForModel('grok-4.7[effort=xhigh,fast=true]'),
        isNull,
      );
      expect(catalog.variantForModel(''), isNull);
    });

    test('does not invent a fast slug the catalog omitted', () {
      final invented = catalog.slugForEffort(
        'claude-fable-5-1',
        effort: 'high',
        thinking: false,
        fast: true,
      );
      expect(invented, 'claude-fable-5-1-high');
      expect(invented, isNot('claude-fable-5-1-high-fast'));
      expect(catalog.variantForModel(invented)!.fast, isFalse);
    });

    test('keeps a published combination when the family changes', () {
      final opus = catalog.variantForModel(
        'claude-opus-4-8-thinking-high-fast',
      )!;
      expect(
        catalog.slugForFamily('claude-sonnet-5', previous: opus),
        'claude-sonnet-5-thinking-high-fast',
      );
    });

    test(
      'falls back to the closest base slug when the combination is missing',
      () {
        final fastGrok = catalog.variantForModel('grok-4.7-xhigh-fast')!;
        expect(
          catalog.slugForFamily('claude-fable-5-1', previous: fastGrok),
          'claude-fable-5-1-high',
        );
        expect(
          catalog.slugForFamily('composer-2.5', previous: fastGrok),
          'composer-2.5',
        );
        expect(
          catalog.slugForFamily('gpt-5.5', previous: fastGrok),
          'gpt-5.5-extra-high',
        );
        expect(
          catalog.slugForFamily(
            'gpt-5.4',
            previous: catalog.variantForModel('grok-4.7-xhigh'),
          ),
          'gpt-5.4-high',
        );
      },
    );

    test('picks a base slug when the family is first selected', () {
      expect(catalog.slugForFamily('composer-2.5'), 'composer-2.5');
      expect(catalog.slugForFamily('grok-4.7'), 'grok-4.7-xhigh');
      expect(catalog.slugForFamily('auto'), 'auto');
    });

    test('effort changes stay on a published slug for that effort', () {
      final opus = catalog.variantForModel(
        'claude-opus-4-8-thinking-high-fast',
      )!;
      expect(
        catalog.slugForEffort(
          opus.family,
          effort: 'medium',
          thinking: opus.thinking,
          fast: opus.fast,
        ),
        'claude-opus-4-8-thinking-medium',
      );
      expect(
        catalog.slugForEffort(
          'claude-opus-4-8',
          effort: 'low',
          thinking: true,
          fast: true,
        ),
        'claude-opus-4-8-low-fast',
      );
      expect(
        catalog.slugForEffort(
          'grok-4.7',
          effort: 'xhigh',
          thinking: false,
          fast: true,
        ),
        'grok-4.7-xhigh-fast',
      );
    });

    test('titles a slug-shaped label from the family id', () {
      final catalog = CursorModelCatalog.fromOptions(const <ManagedAgentOption>[
        ManagedAgentOption('claude-fable-5-1-high', 'claude-fable-5-1-high'),
      ]);
      expect(catalog.familyById('claude-fable-5-1')!.label, 'Claude Fable 5.1');
    });
  });
}

void _expectSlug(
  String id, {
  required String family,
  String? effort,
  bool thinking = false,
  bool fast = false,
}) {
  final parsed = parseCursorModelSlug(id);
  expect(parsed, isNotNull, reason: id);
  expect(parsed!.id, id, reason: id);
  expect(parsed.family, family, reason: id);
  expect(parsed.effort, effort, reason: id);
  expect(parsed.thinking, thinking, reason: id);
  expect(parsed.fast, fast, reason: id);
}

final List<ManagedAgentOption> _exampleModels = <ManagedAgentOption>[
  const ManagedAgentOption('grok-4.7-xhigh-fast', 'Grok 4.7 Extra High Fast'),
  const ManagedAgentOption('grok-4.7-xhigh', 'Grok 4.7 Extra High'),
  const ManagedAgentOption('claude-fable-5-1-high', 'Claude Fable 5.1 High'),
  const ManagedAgentOption(
    'claude-fable-5-1-thinking-high',
    'Claude Fable 5.1 Thinking High',
  ),
  const ManagedAgentOption(
    'claude-opus-4-8-thinking-high-fast',
    'Claude Opus 4.8 Thinking High Fast',
  ),
  const ManagedAgentOption('claude-opus-4-8-high', 'Claude Opus 4.8 High'),
  const ManagedAgentOption(
    'claude-opus-4-8-thinking-high',
    'Claude Opus 4.8 Thinking High',
  ),
  const ManagedAgentOption(
    'claude-opus-4-8-thinking-medium',
    'Claude Opus 4.8 Thinking Medium',
  ),
  const ManagedAgentOption(
    'claude-opus-4-8-low-fast',
    'Claude Opus 4.8 Low Fast',
  ),
  const ManagedAgentOption('claude-opus-4-8-low', 'Claude Opus 4.8 Low'),
  const ManagedAgentOption('composer-2.5-fast', 'Composer 2.5 Fast'),
  const ManagedAgentOption('composer-2.5', 'Composer 2.5'),
  const ManagedAgentOption(
    'claude-4.6-opus-high-thinking',
    'Claude 4.6 Opus High Thinking',
  ),
  const ManagedAgentOption(
    'claude-4.5-sonnet-thinking',
    'Claude 4.5 Sonnet Thinking',
  ),
  const ManagedAgentOption(
    'gpt-5.5-extra-high-fast',
    'GPT 5.5 Extra High Fast',
  ),
  const ManagedAgentOption('gpt-5.5-extra-high', 'GPT 5.5 Extra High'),
  const ManagedAgentOption('gpt-5.5-high', 'GPT 5.5 High'),
  const ManagedAgentOption('gpt-5.4-max', 'GPT 5.4 Max'),
  const ManagedAgentOption('gpt-5.4-high', 'GPT 5.4 High'),
  const ManagedAgentOption('kimi-k2.7-code', 'Kimi K2.7 Code'),
  const ManagedAgentOption('auto', 'Auto'),
  const ManagedAgentOption(
    'claude-sonnet-5-thinking-high-fast',
    'Claude Sonnet 5 Thinking High Fast',
  ),
  const ManagedAgentOption('claude-sonnet-5-high', 'Claude Sonnet 5 High'),
];
