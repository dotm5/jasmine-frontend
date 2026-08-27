import 'dart:convert';

import 'backend_transport.dart';

/// Jasmine JSON bridge v1. Objects are encoded inside the string `params` field;
/// successful results stay strings so existing typed frontend methods can decode
/// them. Keep this wire format stable when changing the transport or backend.
class BackendClient {
  const BackendClient(this.transport);

  final BackendTransport transport;

  Future<String> invoke(String method, dynamic params) async {
    final request = jsonEncode({
      'method': method,
      'params': params is String ? params : jsonEncode(params),
    });
    final response = jsonDecode(await transport.send(request));
    if (response is! Map<String, dynamic> ||
        response['error_message'] is! String ||
        response['response_data'] is! String) {
      throw const FormatException('Invalid Jasmine JSON bridge v1 response');
    }
    final error = response['error_message'] as String;
    if (error.isNotEmpty) {
      throw StateError(error);
    }
    return response['response_data'] as String;
  }
}
