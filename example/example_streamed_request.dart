import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';
import 'package:http/http.dart';

void main() async {
  // Temp file
  final tempDir = (await Directory.systemTemp.createTemp()).path;
  const filename = 'test_file.txt';
  final filepath = '$tempDir/$filename';
  final sink = File(filepath).openWrite();
  final chunk = List.filled(256 * 256, 48);
  const chunkCount = 5000;
  _client('Creating a temporary file');
  for (var i = 0; i < chunkCount; i++) {
    sink.add(chunk);
  }

  await sink.close();
  _client('Temp file size: ${(chunkCount * chunk.length).mb} MB');

  // Server
  final server = await HttpServer.bind('localhost', 8080);
  final serverUrl = 'http://${server.address.host}:${server.port}';
  unawaited(() async {
    await for (final request in server) {
      final response = request.response;
      final url = request.requestedUri;
      _server('Begin request: $url');
      try {
        var received = 0;
        try {
          await request.listen((event) {
            received += event.length;
          }).asFuture<void>();
        } finally {
          _server('Received: ${received.mb} MB');
        }
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
  const timeout = 250;
  final watch = Stopwatch()..start();
  final cts = CancellationTokenSource(Duration(milliseconds: timeout));
  final token = cts.token;
  final client = CancelableClient(token);
  try {
    final request = StreamedRequest("POST", url);
    final file = File(filepath);
    // Make it possible to cancel sending data.
    final stream = file.openRead().asCancelable(token);
    final sink = request.sink;
    request.headers['Content-Type'] = 'text/plain';
    request.contentLength = file.lengthSync();
    stream.listen(
      sink.add,
      onDone: sink.close,
      onError: sink.addError,
      cancelOnError: true,
    );
    _client('Sending streaming request with timeout $timeout ms');
    await client.send(request);
    cts.cancelAfter(null);
    _client('Received response');
  } catch (e) {
    _client('Error: $e at ${watch.elapsedMilliseconds} ms');
  }

  _client('Elapsed ${watch.elapsedMilliseconds} ms');
  await Future<void>.delayed(Duration(seconds: 5));
  File(filepath).deleteSync();
  Directory(tempDir).deleteSync();
  await server.close();
}

void _client(String text) => print('Client: $text');

void _server(String text) => print('Server: $text');

extension on int {
  String get mb => (this / 1e6).toStringAsFixed(2);
}
