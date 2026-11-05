/// Any error from the API, or a network failure (`status` 0).
class GiftingException implements Exception {
  /// Creates an error. [requestId] is the API's request id when it sent one.
  const GiftingException(
    this.status,
    this.type,
    this.message, [
    this.requestId,
  ]);

  /// HTTP status, or 0 when the host could not be reached.
  final int status;

  /// `body.error.type`, `network_error` or `unknown_error`.
  final String type;

  /// A message safe to log. Show your own text to people.
  final String message;

  /// `body.error.request_id`, else the `X-Request-Id` header, else null.
  final String? requestId;

  /// Worth showing as "try again" rather than as a hard failure.
  bool get retryable => status == 0 || status == 429 || status >= 500;

  /// `insufficient_balance`: show your coin store.
  bool get insufficientBalance => type == 'insufficient_balance';

  @override
  String toString() => 'GiftingException($status, $type): $message';
}

/// The name the task brief and the TypeScript SDK use for [GiftingException].
typedef GiftingError = GiftingException;
