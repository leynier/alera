import 'package:alera/src/features/steer/domain/steer_rule.dart';

// State class for the steer module containing all steer rules.
class SteerState {
  const SteerState({
    this.rules = const <SteerRule>[],
    this.isExpanded = false,
    this.maxRules = 20,
  });

  final List<SteerRule> rules;
  final bool isExpanded;
  final int maxRules;

  // Get only active rules sorted by order.
  List<SteerRule> get activeRules {
    return rules
        .where((r) => r.active)
        .toList(growable: false)
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  // Get all rules sorted by order.
  List<SteerRule> get sortedRules {
    return List<SteerRule>.of(rules)
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  // Check if max rules limit is reached.
  bool get isMaxRulesReached => rules.length >= maxRules;

  SteerState copyWith({
    List<SteerRule>? rules,
    bool? isExpanded,
    int? maxRules,
  }) {
    return SteerState(
      rules: rules ?? this.rules,
      isExpanded: isExpanded ?? this.isExpanded,
      maxRules: maxRules ?? this.maxRules,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'rules': rules.map((r) => r.toJson()).toList(),
      'isExpanded': isExpanded,
      'maxRules': maxRules,
    };
  }

  factory SteerState.fromJson(Map<String, dynamic> json) {
    final rulesList = (json['rules'] as List<dynamic>? ?? <dynamic>[])
        .map((r) => SteerRule.fromJson(r as Map<String, dynamic>))
        .toList();
    return SteerState(
      rules: rulesList,
      isExpanded: json['isExpanded'] as bool? ?? false,
      maxRules: json['maxRules'] as int? ?? 20,
    );
  }
}
