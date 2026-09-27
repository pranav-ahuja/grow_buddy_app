import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Any failure the UI can show to the user as-is.
class GB_ApiException implements Exception {
  final String message;
  final int? statusCode;

  GB_ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Shared plumbing for talking to the GrowBuddy backend.
class GB_ApiClient {
  static const Duration _timeout = Duration(seconds: 15);

  /// The client every request goes through.
  ///
  /// A field rather than the top-level `http.post`/`get`/`patch` helpers so
  /// tests can swap in a `MockClient` and exercise the whole app without a
  /// server. Production code never assigns it.
  @visibleForTesting
  static http.Client client = http.Client();

  static Map<String, String> _headers({String? token}) {
    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  static Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    return _send(
      () => client.post(
        Uri.parse(url),
        headers: _headers(token: token),
        body: jsonEncode(body),
      ),
    );
  }

  static Future<Map<String, dynamic>> patchJson(
    String url,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    return _send(
      () => client.patch(
        Uri.parse(url),
        headers: _headers(token: token),
        body: jsonEncode(body),
      ),
    );
  }

  static Future<Map<String, dynamic>> getJson(
    String url, {
    String? token,
  }) async {
    return _send(
      () => client.get(Uri.parse(url), headers: _headers(token: token)),
    );
  }

  /// A GET whose body is a JSON array — the list endpoints, e.g. `/classes`.
  ///
  /// [_decodeBody] wraps a top-level array as `{"data": [...]}` so that every
  /// response can travel as a map; this unwraps it again.
  static Future<List<Map<String, dynamic>>> getJsonList(
    String url, {
    String? token,
  }) async {
    final Map<String, dynamic> decoded = await getJson(url, token: token);
    final dynamic items = decoded["data"];
    if (items is! List) {
      throw GB_ApiException("The server sent back something unexpected.");
    }
    return items.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> putJson(
    String url,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    return _send(
      () => client.put(
        Uri.parse(url),
        headers: _headers(token: token),
        body: jsonEncode(body),
      ),
    );
  }

  /// A DELETE whose reply is ignored — success is simply not throwing.
  ///
  /// Kept for the routes that still answer 204. Where the answer matters, use
  /// [deleteJson]: since the approval queue arrived, deleting a class or a
  /// pupil can come back either "done" or "waiting for the principal", and
  /// that is a body to read rather than a status to assume.
  static Future<void> delete(
    String url, {
    String? token,
  }) async {
    await _send(
      () => client.delete(Uri.parse(url), headers: _headers(token: token)),
    );
  }

  /// A DELETE that returns what the server said.
  static Future<Map<String, dynamic>> deleteJson(
    String url, {
    String? token,
  }) async {
    return _send(
      () => client.delete(Uri.parse(url), headers: _headers(token: token)),
    );
  }

  static Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on SocketException {
      throw GB_ApiException(
        "Can't reach the server. Check that the backend is running and that "
        "kApiBaseUrl points at it.",
      );
    } on TimeoutException {
      throw GB_ApiException("The server took too long to respond. Try again.");
    } catch (error) {
      throw GB_ApiException("Network error: $error");
    }

    final decoded = _decodeBody(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    // The backend always sends errors as {"detail": "..."}.
    final detail = decoded["detail"];
    throw GB_ApiException(
      detail is String && detail.isNotEmpty
          ? detail
          : "Request failed (${response.statusCode})",
      statusCode: response.statusCode,
    );
  }

  static Map<String, dynamic> _decodeBody(http.Response response) {
    if (response.body.isEmpty) return {};
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : {"data": decoded};
    } on FormatException {
      // A proxy or crash page rather than our API.
      return {};
    }
  }
}