import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';
import 'package:http/http.dart';

void main() async {
  final server = await HttpServer.bind('localhost', 8080);
  final serverUrl = 'http://${server.address.host}:${server.port}';

  unawaited(() async {
    await for (HttpRequest request in server) {
      final response = request.response;
      _server('Receiving request');
      try {
        _server('Begin operation');
        await for (final _ in request) {
          _server('Receiving data');
        }

        _server('End operation');
      } catch (e) {
        _server('Error: $e');
      } finally {
        _server('Send response');
        await response.close();
      }
    }
  }());

  final cts = CancellationTokenSource(Duration(seconds: 1));
  final token = cts.token;
  final client = CancelableClient(token);
  try {
    final request = MultipartRequest("POST", Uri.parse(serverUrl));
    const partSize = 0xffff;
    final dummyData = List.filled(partSize, 48);
    final stream = Stream.periodic(Duration(milliseconds: 350), (_) {
      _client('Sending data');
      return dummyData;
    });

    const fileSize = 0xffffffff;
    final file = MultipartFile(
      'file',
      stream.asCancelable(token, throwIfCanceled: true),
      fileSize,
    );
    request.files.add(file);
    _client('Sending multipart request');
    await client.send(request);
    _client('Received request');
  } catch (e) {
    _client('Error: $e');
  }

  _client('Done');
  Timer(Duration(seconds: 2), () async {
    _client('Shuting down a server');
    await server.close();
  });
}

void _client(String text) {
  print('Client: $text');
}

void _server(String text) {
  print('Server: $text');
}
