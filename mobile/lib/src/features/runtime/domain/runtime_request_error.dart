/// A request the runtime refused. It stays a [StateError] with the runtime's
/// text, as every caller expects, and adds the additive `errorCode` so a
/// screen can explain a known refusal in its own words.
class RuntimeRequestError extends StateError {
  RuntimeRequestError(super.message, {this.code});

  final String? code;
}
