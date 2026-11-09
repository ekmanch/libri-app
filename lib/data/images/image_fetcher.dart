import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../net/http_transport.dart';
import '../user_agent.dart';

/// The server answered, but not with an image.
class ImageFetchException implements Exception {
  const ImageFetchException(this.status, {this.message = ''});

  final int status;
  final String message;

  @override
  String toString() => 'ImageFetchException($status $message)';
}

/// Downloads an image. Throws [NetworkUnreachable] when offline and
/// [ImageFetchException] for any other failure.
abstract class ImageFetcher {
  Future<Uint8List> fetch(Uri url);
}

class HttpImageFetcher implements ImageFetcher {
  HttpImageFetcher(
    this._client, {
    this.timeout = defaultHttpTimeout,
    String? userAgent,
  }) : userAgent = userAgent ?? lookupUserAgent;

  final http.Client _client;
  final Duration timeout;
  final String userAgent;

  @override
  Future<Uint8List> fetch(Uri url) async {
    final response = await sendOrOffline(
      () => _client.get(url, headers: {'User-Agent': userAgent}),
      timeout: timeout,
    );
    if (response.statusCode != 200) {
      throw ImageFetchException(
        response.statusCode,
        message: response.reasonPhrase ?? '',
      );
    }
    final type = response.headers['content-type'] ?? '';
    if (response.bodyBytes.isEmpty || type.startsWith('text/')) {
      throw ImageFetchException(200, message: 'not an image ($type)');
    }
    return response.bodyBytes;
  }
}
