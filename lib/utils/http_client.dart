import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Creates an HTTP client that bypasses SSL certificate verification.
/// Use this ONLY for development/testing with self-signed certificates.
/// For production, use proper SSL certificates from a trusted CA.
class HttpClientFactory {
  static http.Client createClient({bool allowSelfSigned = false}) {
    if (allowSelfSigned) {
      final httpClient = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      return IOClient(httpClient);
    }
    return http.Client();
  }
}
