import 'dart:convert';
import 'package:http/http.dart' as http;
import 'constants.dart';

class ApiService {
  static String get baseUrl => kApiBaseUrl;

  static Map<String, String> getHeaders(String? token) {
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      kAppSecretHeader: kAppSecretKey,
    };
  }

  /// Helper to fetch URL with headers
  static Future<http.Response> get(String endpoint, {String? token}) async {
    final uri = endpoint.startsWith('http') ? Uri.parse(endpoint) : Uri.parse('$baseUrl$endpoint');
    return http.get(uri, headers: getHeaders(token));
  }

  /// Helper to post JSON data
  static Future<http.Response> post(String endpoint, {required Map<String, dynamic> body, String? token}) async {
    final uri = endpoint.startsWith('http') ? Uri.parse(endpoint) : Uri.parse('$baseUrl$endpoint');
    return http.post(uri, headers: getHeaders(token), body: jsonEncode(body));
  }
}
