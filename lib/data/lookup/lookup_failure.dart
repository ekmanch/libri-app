import 'lookup_match.dart';

/// Why a lookup gave no answer. The screen words each one; no provider
/// names reach the UI.
enum LookupFailure {
  /// No network, or the provider never answered.
  offline,

  /// The provider needs a key this build was made without.
  notConfigured,

  /// The provider refused for now (429, or its own quota answer).
  rateLimited,

  /// Anything else: an error status, a malformed answer.
  other,
}

class LookupException implements Exception {
  const LookupException(this.failure, {this.status, this.message = ''});

  final LookupFailure failure;
  final int? status;
  final String message;

  @override
  String toString() =>
      'LookupException(${failure.name}'
      '${status == null ? '' : ', $status'}'
      '${message.isEmpty ? '' : ': $message'})';
}

/// Thrown by a source that asks more than one provider when some of them
/// answered and some did not: [matches] are what the ones that answered
/// found, [failure] why the others gave nothing. The search counts it as
/// one answer and one failure.
class PartialLookupException extends LookupException {
  const PartialLookupException(
    this.matches,
    super.failure, {
    super.status,
    super.message,
  });

  final List<LookupMatch> matches;
}
