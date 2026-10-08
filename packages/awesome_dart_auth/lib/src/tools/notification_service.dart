import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Configuration for an outbound email delivery endpoint.
@immutable
class MailerConfig {
  /// Creates a mailer configuration.
  const MailerConfig({
    required this.endpoint,
    required this.apiKey,
    required this.fromAddress,
    this.fromName,
  });

  /// HTTP endpoint that accepts a POST with the email payload.
  final String endpoint;

  /// API key sent as a bearer token to the mailer endpoint.
  final String apiKey;

  /// Sender address.
  final String fromAddress;

  /// Optional human-readable sender name.
  final String? fromName;
}

/// Configuration for an outbound SMS delivery endpoint.
@immutable
class SmsConfig {
  /// Creates an SMS configuration.
  const SmsConfig({
    required this.endpoint,
    required this.apiKey,
    this.username,
    this.password,
  });

  /// HTTP endpoint that accepts a POST with the SMS payload.
  final String endpoint;

  /// API key sent as a bearer token to the SMS endpoint.
  final String apiKey;

  /// Optional username for basic-auth protected endpoints.
  final String? username;

  /// Optional password for basic-auth protected endpoints.
  final String? password;
}

/// Options for dispatching an outbound email.
@immutable
class SendEmailOptions {
  /// Creates send-email options.
  const SendEmailOptions({
    required this.to,
    required this.subject,
    this.html,
    this.text,
  });

  /// Recipient email address.
  final String to;

  /// Email subject line.
  final String subject;

  /// HTML body.
  final String? html;

  /// Plain-text body.
  final String? text;
}

/// Options for dispatching an outbound SMS.
@immutable
class SendSmsOptions {
  /// Creates send-SMS options.
  const SendSmsOptions({required this.to, required this.message});

  /// Recipient phone number in E.164 format.
  final String to;

  /// Message body.
  final String message;
}

/// Standalone multi-channel notification service.
///
/// Wraps an HTTP-based email endpoint and an HTTP-based SMS endpoint.
class NotificationService {
  /// Creates a notification service.
  NotificationService({
    this.email,
    this.sms,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  /// Email delivery configuration.
  final MailerConfig? email;

  /// SMS delivery configuration.
  final SmsConfig? sms;

  final HttpClient _httpClient;

  /// Sends an email via the configured [email] endpoint.
  ///
  /// Throws a [StateError] if no [email] configuration has been provided.
  Future<void> sendEmail(SendEmailOptions options) async {
    final cfg = email;
    if (cfg == null) {
      throw StateError(
        'No MailerConfig provided to NotificationService. '
        'Construct NotificationService with an email: MailerConfig(…) to '
        'enable email delivery.',
      );
    }
    await _postJson(
      cfg.endpoint,
      cfg.apiKey,
      <String, Object?>{
        'to': options.to,
        'subject': options.subject,
        if (options.html != null) 'html': options.html,
        if (options.text != null) 'text': options.text,
        'from': cfg.fromAddress,
        if (cfg.fromName != null) 'fromName': cfg.fromName,
      },
    );
  }

  /// Sends an SMS via the configured [sms] endpoint.
  ///
  /// Throws a [StateError] if no [sms] configuration has been provided.
  Future<void> sendSms(SendSmsOptions options) async {
    final cfg = sms;
    if (cfg == null) {
      throw StateError(
        'No SmsConfig provided to NotificationService. '
        'Construct NotificationService with a sms: SmsConfig(…) to '
        'enable SMS delivery.',
      );
    }
    await _postJson(
      cfg.endpoint,
      cfg.apiKey,
      <String, Object?>{'to': options.to, 'message': options.message},
      username: cfg.username,
      password: cfg.password,
    );
  }

  /// Posts [body] as JSON to [url] using [apiKey] for bearer-token auth.
  Future<void> _postJson(
    String url,
    String apiKey,
    Map<String, Object?> body, {
    String? username,
    String? password,
  }) async {
    final uri = Uri.parse(url);
    final request = await _httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    if (username != null && password != null) {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      request.headers.set('authorization', 'Basic $credentials');
      request.headers.set('x-api-key', apiKey);
    } else {
      request.headers.set('authorization', 'Bearer $apiKey');
    }
    request.write(jsonEncode(body));
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Notification delivery failed for $url with status '
        '${response.statusCode}.',
      );
    }
  }
}
