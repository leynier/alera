import 'package:alera/src/features/agent_profiles/domain/cursor_model_variant.dart';
import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';

/// Discovered slugs that share a family.
final class CursorModelFamily {
  const CursorModelFamily({
    required this.id,
    required this.label,
    required this.variants,
  });

  final String id;
  final String label;
  final List<CursorModelVariant> variants;

  List<String> get efforts {
    final present = <String>{
      for (final variant in variants)
        if (variant.effort != null) variant.effort!,
    };
    return <String>[
      for (final token in cursorEffortTokens)
        if (present.contains(token)) token,
    ];
  }

  bool get hasThinking => variants.any((variant) => variant.thinking);

  bool get hasFast => variants.any((variant) => variant.fast);

  /// The family publishes both an effort token and a slug with no effort.
  bool get offersBareEffort {
    return efforts.isNotEmpty &&
        variants.any((variant) => variant.effort == null);
  }

  CursorModelVariant? match({
    required String? effort,
    required bool thinking,
    required bool fast,
  }) {
    for (final variant in variants) {
      if (variant.effort == effort &&
          variant.thinking == thinking &&
          variant.fast == fast) {
        return variant;
      }
    }
    return null;
  }

  bool canToggleThinking(CursorModelVariant current) {
    return match(
          effort: current.effort,
          thinking: !current.thinking,
          fast: current.fast,
        ) !=
        null;
  }

  bool canToggleFast(CursorModelVariant current) {
    return match(
          effort: current.effort,
          thinking: current.thinking,
          fast: !current.fast,
        ) !=
        null;
  }
}

/// Groups a discovered Cursor model list and resolves controls back to a slug.
final class CursorModelCatalog {
  const CursorModelCatalog._({required this.families, required this._byId});

  final List<CursorModelFamily> families;
  final Map<String, CursorModelVariant> _byId;

  factory CursorModelCatalog.fromOptions(List<ManagedAgentOption> options) {
    final byId = <String, CursorModelVariant>{};
    final grouped = <String, List<CursorModelVariant>>{};
    final familyOrder = <String>[];
    for (final (index, option) in options.indexed) {
      final id = option.value.trim();
      if (id.isEmpty || byId.containsKey(id)) {
        continue;
      }
      final parsed = parseCursorModelSlug(id);
      if (parsed == null) {
        continue;
      }
      final variant = CursorModelVariant(
        id: parsed.id,
        family: parsed.family,
        effort: parsed.effort,
        thinking: parsed.thinking,
        fast: parsed.fast,
        label: option.label,
        catalogIndex: index,
      );
      byId[id] = variant;
      grouped
          .putIfAbsent(parsed.family, () {
            familyOrder.add(parsed.family);
            return <CursorModelVariant>[];
          })
          .add(variant);
    }
    final families = <CursorModelFamily>[
      for (final familyId in familyOrder)
        CursorModelFamily(
          id: familyId,
          label: _familyLabel(grouped[familyId]!),
          variants: List<CursorModelVariant>.unmodifiableOf(grouped[familyId]!),
        ),
    ];
    return CursorModelCatalog._(
      families: List<CursorModelFamily>.unmodifiableOf(
        _disambiguateFamilyLabels(families),
      ),
      byId: Map<String, CursorModelVariant>.unmodifiableOf(byId),
    );
  }

  /// A stored id drives the variant controls only when it parses and Cursor
  /// published that exact slug.
  CursorModelVariant? variantForModel(String? modelId) {
    if (modelId == null) {
      return null;
    }
    final id = modelId.trim();
    if (id.isEmpty || parseCursorModelSlug(id) == null) {
      return null;
    }
    return _byId[id];
  }

  CursorModelFamily? familyById(String familyId) {
    for (final family in families) {
      if (family.id == familyId) {
        return family;
      }
    }
    return null;
  }

  /// Picks a published slug for [familyId].
  ///
  /// Keeps [previous] effort, thinking, and fast when that combination exists.
  /// Otherwise prefers the non-fast, non-thinking slug whose effort is closest
  /// to the previous one. With no previous selection, prefers a slug that has
  /// no fast, thinking, or effort token, then the first other base slug.
  String? slugForFamily(String familyId, {CursorModelVariant? previous}) {
    final family = familyById(familyId);
    if (family == null || family.variants.isEmpty) {
      return null;
    }
    if (previous == null) {
      return _preferredBase(family).id;
    }
    final exact = family.match(
      effort: previous.effort,
      thinking: previous.thinking,
      fast: previous.fast,
    );
    if (exact != null) {
      return exact.id;
    }
    final plain = family.variants
        .where((variant) => !variant.thinking && !variant.fast)
        .toList(growable: false);
    if (plain.isNotEmpty) {
      return _closest(
        plain,
        effort: previous.effort,
        preferThinking: false,
        preferFast: false,
      ).id;
    }
    return _closest(
      family.variants,
      effort: previous.effort,
      preferThinking: previous.thinking,
      preferFast: previous.fast,
    ).id;
  }

  /// Picks a published slug with [effort], keeping thinking and fast when
  /// that combination exists.
  String? slugForEffort(
    String familyId, {
    required String? effort,
    required bool thinking,
    required bool fast,
  }) {
    final family = familyById(familyId);
    if (family == null) {
      return null;
    }
    final exact = family.match(effort: effort, thinking: thinking, fast: fast);
    if (exact != null) {
      return exact.id;
    }
    final candidates = family.variants
        .where((variant) => variant.effort == effort)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    return _closest(
      candidates,
      effort: effort,
      preferThinking: thinking,
      preferFast: fast,
    ).id;
  }
}

CursorModelVariant _preferredBase(CursorModelFamily family) {
  final plain = family.variants
      .where((variant) => !variant.thinking && !variant.fast)
      .toList(growable: false);
  final pool = plain.isNotEmpty ? plain : family.variants;
  for (final variant in pool) {
    if (variant.effort == null) {
      return variant;
    }
  }
  return pool.first;
}

CursorModelVariant _closest(
  List<CursorModelVariant> variants, {
  required String? effort,
  required bool preferThinking,
  required bool preferFast,
}) {
  final ranked = List<CursorModelVariant>.of(variants);
  ranked.sort((a, b) {
    final byDistance = _effortDistance(
      effort,
      a.effort,
    ).compareTo(_effortDistance(effort, b.effort));
    if (byDistance != 0) {
      return byDistance;
    }
    if (effort != null) {
      final aExact = a.effort == effort;
      final bExact = b.effort == effort;
      if (aExact != bExact) {
        return aExact ? -1 : 1;
      }
    }
    final aThinking = a.thinking == preferThinking;
    final bThinking = b.thinking == preferThinking;
    if (aThinking != bThinking) {
      return aThinking ? -1 : 1;
    }
    final aFast = a.fast == preferFast;
    final bFast = b.fast == preferFast;
    if (aFast != bFast) {
      return aFast ? -1 : 1;
    }
    final byRank = _effortRank(a.effort).compareTo(_effortRank(b.effort));
    if (byRank != 0) {
      return byRank;
    }
    return a.catalogIndex.compareTo(b.catalogIndex);
  });
  return ranked.first;
}

int _effortRank(String? effort) {
  return switch (effort) {
    null => -1,
    'none' => 0,
    'minimal' => 1,
    'low' => 2,
    'medium' => 3,
    'high' => 4,
    // Same level, two spellings.
    'xhigh' || 'extra-high' => 5,
    'max' => 6,
    _ => 50,
  };
}

int _effortDistance(String? previous, String? candidate) {
  if (previous == candidate) {
    return 0;
  }
  if (previous == null || candidate == null) {
    return 100;
  }
  return (_effortRank(previous) - _effortRank(candidate)).abs();
}

String _familyLabel(List<CursorModelVariant> variants) {
  final plain = variants
      .where((variant) => !variant.thinking && !variant.fast)
      .toList(growable: false);
  final pool = plain.isNotEmpty ? plain : variants;
  String? best;
  var bestIndex = 1 << 30;
  for (final variant in pool) {
    final label = _labelForVariant(variant);
    if (best == null ||
        label.length < best.length ||
        (label.length == best.length && variant.catalogIndex < bestIndex)) {
      best = label;
      bestIndex = variant.catalogIndex;
    }
  }
  return best ?? _titleFromFamilyId(variants.first.family);
}

String _labelForVariant(CursorModelVariant variant) {
  final raw = variant.label.trim();
  if (raw.isEmpty || raw == variant.id || _isSlugShaped(raw)) {
    return _titleFromFamilyId(variant.family);
  }
  var label = raw;
  if (variant.fast) {
    label = _stripLastPhrase(label, 'Fast');
  }
  if (variant.thinking) {
    label = _stripLastPhrase(label, 'Thinking');
  }
  final effort = variant.effort;
  if (effort != null) {
    label = _stripLastPhrase(label, cursorEffortLabel(effort));
    if (effort == 'xhigh') {
      label = _stripLastPhrase(label, 'Xhigh');
    }
  }
  label = label.replaceAll(RegExp(r'\(\s*\)'), '');
  label = label.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  if (label.isEmpty) {
    return _titleFromFamilyId(variant.family);
  }
  return label;
}

bool _isSlugShaped(String label) {
  return label.contains('-') && !label.contains(RegExp(r'\s'));
}

String _stripLastPhrase(String label, String phrase) {
  final pattern = RegExp(
    '\\b${RegExp.escape(phrase)}\\b',
    caseSensitive: false,
  );
  final matches = pattern.allMatches(label).toList(growable: false);
  if (matches.isEmpty) {
    return label;
  }
  final match = matches.last;
  return '${label.substring(0, match.start)}${label.substring(match.end)}';
}

String _titleFromFamilyId(String family) {
  final parts = family.split('-').where((part) => part.isNotEmpty).toList();
  final words = <String>[];
  for (var index = 0; index < parts.length; index++) {
    final part = parts[index];
    if (RegExp(r'^\d+$').hasMatch(part)) {
      final numbers = <String>[part];
      while (index + 1 < parts.length &&
          RegExp(r'^\d+$').hasMatch(parts[index + 1])) {
        index += 1;
        numbers.add(parts[index]);
      }
      words.add(numbers.join('.'));
      continue;
    }
    words.add(_titleToken(part));
  }
  return words.join(' ');
}

String _titleToken(String part) {
  if (part.toLowerCase() == 'gpt') {
    return 'GPT';
  }
  if (part.length <= 3 && RegExp(r'^\d').hasMatch(part)) {
    return part.toUpperCase();
  }
  return '${part[0].toUpperCase()}${part.substring(1)}';
}

List<CursorModelFamily> _disambiguateFamilyLabels(
  List<CursorModelFamily> families,
) {
  final counts = <String, int>{};
  for (final family in families) {
    counts[family.label] = (counts[family.label] ?? 0) + 1;
  }
  if (counts.values.every((count) => count == 1)) {
    return families;
  }
  return <CursorModelFamily>[
    for (final family in families)
      (counts[family.label] ?? 0) > 1
          ? CursorModelFamily(
              id: family.id,
              label: '${family.label} (${family.id})',
              variants: family.variants,
            )
          : family,
  ];
}
