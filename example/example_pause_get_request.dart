import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';
import 'package:multitasking/misc/pause.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_static/shelf_static.dart';

Future<void> main(List<String> args) async {
  // Temp file
  final tempDir = (await Directory.systemTemp.createTemp()).path;
  const filename = 'test_file.txt';
  final filepath = '$tempDir/$filename';
  final sink = File(filepath).openWrite();
  final chunk = List.filled(256 * 256, 48);
  const count = 5000;
  _client('Creating a temporary file');
  for (var i = 0; i < count; i++) {
    sink.add(chunk);
  }

  await sink.close();
  _client('Temp file size: ${(count * chunk.length).mb} MB');

  // Server (shelf_static)
  final staticHandler = createStaticHandler(
    tempDir,
    defaultDocument: 'index.html',
    listDirectories: true,
  );
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_trackResponseStream())
      .addHandler(staticHandler);
  final server = await serve(handler, 'localhost', 8080);
  final serverUrl = 'http://${server.address.host}:${server.port}';
  print('Serving at $serverUrl');

  // Client
  final url = Uri.parse('$serverUrl/$filename');
  const timeout = 5500;
  final watch = Stopwatch()..start();
  final cts = CancellationTokenSource();
  final pts = PauseTokenSource();
  final client = CancelableClient(
    cts.token,
    pauseToken: pts.token,
    responseTimeout: Duration(milliseconds: timeout),
  );

  Timer(Duration(seconds: 5), () async {
    _client('Pause 6 sec, longer than timeout');
    await pts.pause();
    Timer(Duration(seconds: 6), () async {
      _client('Resume aster 6 sec');
      await pts.resume();
    });
  });

  try {
    _client('Send request with response timeout $timeout ms');
    final response = await client.get(url);
    final bodyBytes = response.bodyBytes;
    _client('Received response: ${bodyBytes.length}');
  } catch (e) {
    _client('Error: $e at ${watch.elapsedMilliseconds} ms');
  }

  _client('Elapsed ${watch.elapsedMilliseconds} ms');
  await Future<void>.delayed(Duration(seconds: 3));
  _client('Deleting a temporary file');
  File(filepath).deleteSync();
  Directory(tempDir).deleteSync();
  await server.close();
}

void _client(String text) => print('Client: $text');

void _server(String text) => print('Server: $text');

Middleware _trackResponseStream() {
  return (innerHandler) {
    return (request) async {
      final response = await innerHandler(request);
      final stream = response.read().transform(_Tracker());
      return response.change(
        body: stream,
      );
    };
  };
}

class _Tracker extends StreamTransformerBase<List<int>, List<int>> {
  @override
  Stream<List<int>> bind(Stream<List<int>> stream) {
    return () async* {
      var delay = 0;
      var state = 'Canceled';
      var sent = 0;
      try {
        await Future<void>.delayed(Duration(seconds: 3));
        await for (final event in stream) {
          sent += event.length;
          _server('Delay $delay sec');
          await Future<void>.delayed(Duration(seconds: delay));
          yield event;
          delay++;
        }

        state = 'Done';
      } catch (e) {
        state = 'Error';
        rethrow;
      } finally {
        _server('$state: Sent: ${sent.mb} MB');
      }
    }();
  }
}

extension on int {
  String get mb => (this / 1e6).toStringAsFixed(2);
}
