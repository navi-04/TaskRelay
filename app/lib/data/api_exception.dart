enum ApiErrorKind { network, timeout, unauthorized, upgradeRequired, rateLimited, validation, forbidden, notFound, conflict, server, unknown }

class FieldIssue {
  const FieldIssue(this.path, this.message);
  final String path;
  final String message;
}

/// Everything that can go wrong talking to the server, as one type the UI can reason about.
class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.code, this.status, this.retryAfter, this.issues = const []});

  final ApiErrorKind kind;
  final String message;

  /// The server's machine-readable code (e.g. `not_on_date`, `invalid_recurrence`), when it sent one.
  final String? code;
  final int? status;
  final Duration? retryAfter;
  final List<FieldIssue> issues;

  /// The device could not reach the server (as opposed to the server refusing the request).
  bool get isOffline => kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;

  @override
  String toString() => message;
}

/// A message safe to show to a person.
String friendlyError(Object error) {
  if (error is! ApiException) return 'Something went wrong. Please try again.';
  return switch (error.kind) {
    ApiErrorKind.network => 'Can’t reach TaskRelay. Check your connection and try again.',
    ApiErrorKind.timeout => 'The server took too long to answer. Try again.',
    ApiErrorKind.unauthorized => 'You’ve been signed out. Please sign in again.',
    ApiErrorKind.upgradeRequired => 'This version of TaskRelay is too old. Please update the app.',
    ApiErrorKind.rateLimited => error.retryAfter == null ? 'Too many requests. Try again in a moment.' : 'Too many requests. Try again in ${error.retryAfter!.inSeconds.clamp(1, 3600)} s.',
    ApiErrorKind.server => 'The server had a problem. Try again in a moment.',
    _ => error.message,
  };
}
