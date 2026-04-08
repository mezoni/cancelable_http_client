import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';

Future<void> main(List<String> args) async {
  final server = await HttpServer.bind('localhost', 8080);
  final serverUrl = 'http://${server.address.host}:${server.port}';

  unawaited(() async {
    await for (HttpRequest request in server) {
      final response = request.response;
      final url = request.requestedUri;
      _server('Begin request: $url');
      try {
        response.bufferOutput = false;
        Stream<List<int>> gen() async* {
          const count = 100;
          _server('Total chunks: $count');
          var processed = 0;
          try {
            for (var i = 0; i < count; i++, processed++) {
              _server('Send chunk: $i');
              yield [i];
              await Future<void>.delayed(Duration(seconds: 1));
            }
          } finally {
            _server('Chunks sent: $processed of $count');
          }
        }

        await response.addStream(gen());
      } catch (e) {
        _server('Error: $e');
      } finally {
        _server('End request: $url');
        await response.close();
      }
    }
  }());

  final url = Uri.parse(serverUrl);
  const timeout = 2500;
  final watch = Stopwatch();
  watch.start();
  final cts = CancellationTokenSource(Duration(milliseconds: timeout));
  final token = cts.token;
  final client = CancelableClient(token);
  try {
    _client('Send request with timeout $timeout ms');
    final response = await client.get(url);
    cts.cancelAfter(null);
    final bodyBytes = response.bodyBytes;
    _client('Received response: $bodyBytes');
  } catch (e) {
    watch.stop();
    _client('Error: $e at ${watch.elapsedMilliseconds}');
  }

  _client('Elapsed ${watch.elapsedMilliseconds} ms');
  await Future<void>.delayed(Duration(seconds: 5));
  await server.close();
}

void _client(String text) => print('Client: $text');

void _server(String text) => print('Server: $text');
