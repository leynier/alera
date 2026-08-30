class KeepAliveSnapshot {
  const new({
    required this.active,
    required this.system,
    required this.display,
    this.error,
  });

  const new inactive({this.error})
    : active = false,
      system = false,
      display = false;

  const new active()
    : active = true,
      system = true,
      display = true,
      error = null;

  final bool active;
  final bool system;
  final bool display;
  final String? error;

  bool get hasError => error != null && error!.trim().isNotEmpty;
}
