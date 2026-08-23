import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      () => http.post(
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
      () => http.patch(
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
      () => http.get(Uri.parse(url), headers: _headers(token: token)),
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