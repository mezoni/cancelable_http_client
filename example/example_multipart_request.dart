import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';
import 'package:http/http.dart';

void main() async {
  final server = await HttpServer.bind('localhost', 8080);
  final serverUrl = 'http://${server.address.host}:${server.port}';

  unawaited(() async {
    await for (final request in server) {
      final response = request.response;
      final url = request.requestedUri;
      _server('Begin request: $url');
      try {
        var count = 0;
        await for (final _ in request) {
          _server('Received chunk: $count');
          count++;
        }

        _server('Received all data');
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
  final watch = Stopwatch()..start();
  final cts = CancellationTokenSource(Duration(milliseconds: timeout));
  final token = cts.token;
  final client = CancelableClient(token);
  try {
    final request = MultipartRequest("POST", url);
    const chunkSize = 65536;
    final chunk = List.filled(chunkSize, 48);
    const count = 100;
    Stream<List<int>> generate() async* {
      _client('Total chunks: $count');
      for (var i = 0; i < count; i++) {
        _client('Send chunk: $i');
        yield chunk;
        await Future<void>.delayed(Duration(seconds: 1));
      }
    }

    const fileSize = chunkSize * count;
    final stream = generate().asCancelable(token, throwIfCanceled: true);
    final file = MultipartFile('file', stream, fileSize);
    request.files.add(file);
    _client('Sending multipart request with timeout $timeout ms');
    await client.send(request);
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
