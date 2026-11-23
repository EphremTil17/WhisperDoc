import 'dart:convert';

/// A failed call to a cloud service (Groq, OpenRouter): what went wrong, in
/// a category the app can act on, and a message the user can read.
class CloudError implements Exception {
  const CloudError({
    required this.service,
    required this.type,
    required this.message,
    this.retryAfter,
  });

  /// The service's display name, used in [userMessage].
  final String service;
  final CloudErrorType type;

  /// The service's own explanation, for logs and the generic messages.
  final String message;

  /// How long a rate-limited caller must wait, when the service said.
  final Duration? retryAfter;

  static const int _badRequest = 400;
  static const int _unauthorized = 401;
  static const int _paymentRequired = 402;
  static const int _forbidden = 403;
  static const int _notFound = 404;
  static const int _tooLarge = 413;
  static const int _rateLimited = 429;
  static const int _serverError = 500;

  /// How OpenRouter words a model it doesn't serve: a retired one, or an id
  /// it never had.
  static final RegExp _noSuchModel = RegExp(
    'does not exist|not a valid model id',
    caseSensitive: false,
  );

  /// Parses a non-2xx response. A 400 naming a model that doesn't exist is
  /// [CloudErrorType.modelRetired].

  factory CloudError.fromResponse(
    String service,
    int statusCode,
    String body, {
    Map<String, String> headers = const {},
  }) {
    final detail = _extractMessage(body);
    final type = switch (statusCode) {
      _badRequest when _noSuchModel.hasMatch(detail) =>
        CloudErrorType.modelRetired,
      _badRequest => CloudErrorType.badRequest,
      _unauthorized => CloudErrorType.invalidApiKey,
      // A key without access, or input the service's moderation flagged.
      _forbidden => CloudErrorType.refused,
      _paymentRequired => CloudErrorType.insufficientCredits,
      _notFound => CloudErrorType.modelUnavailable,
      _tooLarge => CloudErrorType.fileTooLarge,
      _rateLimited => CloudErrorType.rateLimited,
      >= _serverError => CloudErrorType.serverError,
      _ => CloudErrorType.unknown,
    };
    final retrySeconds = int.tryParse(headers['retry-after'] ?? '');

    return CloudError(
      service: service,
      type: type,
      message: detail,
      retryAfter: type == CloudErrorType.rateLimited && retrySeconds != null
          ? Duration(seconds: retrySeconds)
          : null,
    );
  }

  /// DNS, socket or timeout: the request never got an answer.
  factory CloudError.network(String service, String reason) => CloudError(
    service: service,
    type: CloudErrorType.networkError,
    message: reason,
  );

  /// Human-readable message for the UI error stream.
  String get userMessage => switch (type) {
    CloudErrorType.invalidApiKey => 'Invalid $service API key. Check Account.',
    CloudErrorType.refused => '$service refused the request: $message',
    CloudErrorType.noAudio =>
      'No audio was recorded. Please check your microphone.',
    CloudErrorType.rateLimited => switch (retryAfter) {
      final Duration delay =>
        '$service rate limit reached. Try again in ${delay.inSeconds} seconds.',
      null => '$service rate limit reached. Please wait and try again.',
    },
    CloudErrorType.insufficientCredits =>
      'Your $service credits ran out. Add credits to keep dictating.',
    CloudErrorType.modelRetired =>
      '$service no longer serves this model. Choose another in Account.',
    CloudErrorType.modelUnavailable =>
      'This model isn’t available on $service right now. '
          'Choose another in Account.',

    CloudErrorType.fileTooLarge =>
      'This recording is too long for $service. Record a shorter clip.',
    CloudErrorType.serverError => '$service is temporarily unavailable.',
    CloudErrorType.networkError =>
      'Cannot reach $service. Check your connection.',
    CloudErrorType.badRequest => '$service request failed: $message',
    CloudErrorType.unknown => '$service error: $message',
  };

  @override
  String toString() => 'CloudError($service, $type): $message';

  static String _extractMessage(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final error = json['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) return message;
        }
      }
    } on FormatException {
      // Not JSON: the body itself is the best explanation there is.
    }

    return body.isNotEmpty ? body : 'Unknown error';
  }
}

/// Categories of cloud service failures.
enum CloudErrorType {
  badRequest,
  invalidApiKey,

  /// The key was valid but the service would not do it (403).
  refused,
  insufficientCredits,

  /// The clip was empty, so nothing was sent.
  noAudio,

  /// The service no longer offers the model at all.
  modelRetired,

  /// No host can serve the model under the request's constraints (privacy).
  modelUnavailable,

  fileTooLarge,
  rateLimited,
  serverError,
  networkError,
  unknown,
}
