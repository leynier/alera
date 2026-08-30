class AgentUsagePeriodMemory({int initialDays = 7}) {
  this : _days = initialDays {
    _validate(initialDays);
  }

  int _days;

  int get days => _days;

  void select(int days) {
    _validate(days);
    _days = days;
  }

  static void _validate(int days) {
    if (days != 7 && days != 30 && days != 90) {
      throw ArgumentError.value(days, 'days', 'Must be 7, 30, or 90.');
    }
  }
}

final agentUsagePeriodMemory = AgentUsagePeriodMemory();
