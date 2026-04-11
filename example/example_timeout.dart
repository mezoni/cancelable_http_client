import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';

Future<void> main(List<String> args) async {
  // Server
  final server = await HttpServer.bind('localhost', 8080);
  final serverUrl = 'http://${server.address.host}:${server.port}';
  unawaited(() async {
    await for (final request in server) {
      final response = request.response;
      final url = request.requestedUri;
      _server('Begin request: $url');
      try {
        await Future<void>.delayed(Duration(seconds: 5));
      } catch (e) {
        _server('Error: $e');
      } finally {
        _server('End request: $url');
        await response.close();
      }
    }
  }());

  // Client
  final url = Uri.parse(serverUrl);
  const timeout = 3000;
  final watch = Stopwatch()..start();
  final cts = CancellationTokenSource(Duration(milliseconds: timeout));
  final token = cts.token;
  final client = CancelableClient(token);
  try {
    _client('Send request with timeout $timeout ms');
    await client.get(url);
    cts.cancelAfter(null);
    _client('Received response');
  } catch (e) {
    _client('Error: $e at ${watch.elapsedMilliseconds} ms');
  }

  _client('Elapsed ${watch.elapsedMilliseconds} ms');
  await Future<void>.delayed(Duration(seconds: 5));
  await server.close();
}

void _client(String text) => print('Client: $text');

void _server(String text) => print('Server: $text');
