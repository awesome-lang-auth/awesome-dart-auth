import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:awesome_dart_auth/src/contracts/webhook_store.dart';
import 'package:awesome_dart_auth/src/webhooks/webhook_signer.dart';

/// Sends outgoing webhook events with retry/backoff and optional HMAC signing.
class WebhookSender {
  /// Creates a webhook sender.
  WebhookSender({
    HttpClient? httpClient,
    Future<void> Function(Duration delay)? delay,
  }) : _httpClient = httpClient ?? HttpClient(),
       _delay = delay ?? Future<void>.delayed;

  final HttpClient _httpClient;
  final Future<void> Function(Duration delay) _delay;

  /// Delivers [event] to [config.url], retrying transient failures.
  Future<void> send(WebhookConfig config, OutgoingWebhookEvent event) async {
    if (!config.isActive) return;

    final maxRetries = config.maxRetries ?? 3;
    final baseDelay = config.retryDelayMs ?? const Duration(seconds: 1);
    final body = jsonEncode(event.toJson());

    var attempt = 0;
    while (attempt <= maxRetries) {
      final ok = await _sendOnce(config: config, event: event, body: body);
      if (ok || attempt >= maxRetries) return;
      attempt++;
      await _delay(baseDelay * (1 << (attempt - 1)));
    }
  }

  Future<bool> _sendOnce({
    required WebhookConfig config,
    required OutgoingWebhookEvent event,
    required String body,
  }) async {
    try {
      final uri = Uri.parse(config.url);
      final request = await _httpClient.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('x-webhook-event', event.event);
      request.headers.set('x-webhook-timestamp', event.timestamp.toIso8601String());
      if (config.secret case final secret?) {
        request.headers.set('x-webhook-signature', WebhookSigner(secret).sign(body));
      }
      request.write(body);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Object {
      return false;
    }
  }
}
