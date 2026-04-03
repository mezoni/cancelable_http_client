import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';
import 'package:http/http.dart';
import 'package:mime/mime.dart';

void main() async {
  final (demoServer, serverUrl) = await _demoServer();
  final cts = CancellationTokenSource();
  final token = cts.token;

  final file = File('__my__file.txt');
  file.writeAsBytesSync(List.filled(1 * 1024 * 1024, 48));

  unawaited(_hack.future.then((_) {
    _client('Canceling');
    cts.cancel();
  }));

  final uri = Uri.parse('$serverUrl/upload');
  try {
    await exampleMultipartRequest(file, uri, token);
  } catch (e) {
    _client('Error: $e');
  } finally {
    file.deleteSync();
    Timer(Duration(seconds: 3), () async {
      await demoServer.close();
    });
  }
}

final _hack = Completer<void>();

Future<void> exampleMultipartRequest(
    File file, Uri uri, CancellationToken token) async {
  token.throwIfCanceled();
  final request = MultipartRequest('POST', uri);
  final fp = file.openRead().asCancelable(token, throwIfCanceled: true);
  final fileLength = file.lengthSync();
  request.files.add(MultipartFile('file', fp, fileLength, filename: file.path));
  final client = CancelableClient(token);
  final response = await client.send(request);
  if (response.statusCode == 200) {
    _client('Uploaded!');
  }
}

void _client(String text) {
  print('Client: $text');
}

Future<(HttpServer, String)> _demoServer() async {
  final server = await HttpServer.bind('localhost', 8080);
  final serverUrl = 'http://${server.address.host}:${server.port}';
  _server('Running on $serverUrl');

  Future<void> handleUpload(HttpRequest request) async {
    final contentType = request.headers.contentType;
    if (contentType == null) {
      throw HttpException('contentType');
    }

    final mimeType = contentType.mimeType;
    if (mimeType != 'multipart/form-data') {
      throw HttpException('mime-type: $mimeType');
    }

    final boundary = contentType.parameters['boundary'];
    if (boundary == null) {
      throw HttpException('boundary');
    }

    final transformer = MimeMultipartTransformer(boundary);
    final parts = request.cast<List<int>>().transform(transformer);
    final StreamSubscription<MimeMultipart> sub;
    sub = parts.listen((part) async {
      final headers = part.headers;
      final contentDisposition = headers['content-disposition'];
      if (contentDisposition == null) {
        throw HttpException('content-disposition');
      }

      _server('contentDisposition: $contentDisposition');
      var length = 0;
      await for (final data in part) {
        final byteCount = data.length;
        length += byteCount;
        _server('Received: $length (+$byteCount)');

        if (length > 524288) {
          if (!_hack.isCompleted) {
            _hack.complete();
          }
        }
      }

      _server('Saved: $length');
    });

    final completer = Completer<void>();
    sub.onDone(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    sub.onError((Object e, StackTrace? s) {
      if (!completer.isCompleted) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  unawaited(() async {
    await for (HttpRequest request in server) {
      _server('Begin request ${request.requestedUri}');
      final response = request.response;
      Object? exception;
      try {
        if (request.method == 'POST' && request.uri.path == '/upload') {
          await handleUpload(request);
        } else {
          request.response
            ..statusCode = HttpStatus.methodNotAllowed
            ..write('Unsupported request');
        }
      } catch (e) {
        exception = e;
        _server('Exception $exception');
      } finally {
        _server('End request ${request.requestedUri}');
        await response.close();
      }
    }
  }());

  return (server, serverUrl);
}

void _server(String text) {
  print('Server: $text');
}
