# cancelable_http_client

A cancelable HTTP client is a wrapper over `http.Client` that allows to cancel a request or the operation of receiving data from the response or the operation of sending data via request.

Version: 1.0.0

[![Pub Package](https://img.shields.io/pub/v/cancelable_http_client.svg)](https://pub.dev/packages/cancelable_http_client)
[![Pub Monthly Downloads](https://img.shields.io/pub/dm/cancelable_http_client.svg)](https://pub.dev/packages/cancelable_http_client/score)
[![GitHub Issues](https://img.shields.io/github/issues/mezoni/cancelable_http_client.svg)](https://github.com/mezoni/cancelable_http_client/issues)
[![GitHub Forks](https://img.shields.io/github/forks/mezoni/cancelable_http_client.svg)](https://github.com/mezoni/cancelable_http_client/forks)
[![GitHub Stars](https://img.shields.io/github/stars/mezoni/cancelable_http_client.svg)](https://github.com/mezoni/cancelable_http_client/stargazers)
[![GitHub License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://raw.githubusercontent.com/mezoni/cancelable_http_client/main/LICENSE)

## About this software

This software is a small library that implements the ability to cancel HTTP operations using a [Client](https://pub.dev/documentation/http/latest/http/Client-class.html) from the [http](https://pub.dev/packages/http) package.  
This is implemented using a composition of class [BaseClient](https://pub.dev/documentation/http/latest/http/BaseClient-class.html) and class [CancellationToken](https://pub.dev/documentation/multitasking/latest/multitasking/CancellationToken-class.html).
When a cancellation request is made, the token cancels the HTTP operation.

The result of the cancellation is the exception [TaskCanceledException](https://pub.dev/documentation/multitasking/latest/multitasking/TaskCanceledException-class.html), which indicates that the operation did not complete successfully.

Canceling an HTTP operation on the client does not mean cancelling the operation on the server (except when sending streaming data to the server).  
Also cancel operations do not close the client.

The operating algorithm is as follows.  

**Receiving data from the server**.  
If a cancellation request is initiated before a response is received from the server, the response is ignored and the operation of receiving data from the server is cancelled immediately after receiving a response.  
If a cancellation request is initiated after a response is received from the server, the operation to receive data from the server is canceled immediately.  

**Sending multipart data to the server.**  
Before sending a request, the client prepares the data to be sent.  
Data transfer is performed through streams for each part independently.  
These streams must be submitted to the request as [cancelable](https://pub.dev/documentation/multitasking/latest/multitasking/StreamExtension/asCancelable.html) streams (that is, supporting the cancel operation and throwing the  `TaskCanceledException` exception).  
Initiating a cancellation request  cancels the sending of data through these streams, which causes the server to return an error stating that the connection was closed while receiving data. Until this response is received from the server, the client throws the `TaskCanceledException` exception and ignores the response from the server.  

## Example receiving data

```dart
import 'dart:async';
import 'dart:convert';

import 'package:cancelable_http_client/cancelable_http_client.dart';
import 'package:http/http.dart';

Future<void> main() async {
  for (final timeout in [0, 50, 1000]) {
    final cts = CancellationTokenSource();
    final timer = Timer(Duration(milliseconds: timeout), () {
      print('Canceling');
      cts.cancel();
    });

    final token = cts.token;
    final client = CancelableClient(token);
    final url = Uri.parse('https://pub.dev/api/package-names');
    Response? response;
    try {
      response = await client.get(url);
    } on TaskCanceledException {
      print('Canceled');
    } finally {
      timer.cancel();
    }

    if (response != null) {
      if (response.statusCode != 200) {
        throw StateError('Http error (${response.statusCode})');
      }

      final body = response.body;
      final map = jsonDecode(body) as Map;
      final list = map['packages'];
      print('First names: ${list.take(5)}');
    }

    print('-' * 40);
  }
}

```

Output:

```txt
Canceling
Canceled
----------------------------------------
Canceling
Canceled
----------------------------------------
First names: (Autolinker, Babylon, DartDemoCLI, FileTeCouch, Flutter_Nectar)
----------------------------------------
```

## Example sending data

```dart
import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';
import 'package:http/http.dart';
import 'package:mime/mime.dart';
import 'package:multitasking/multitasking.dart';

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

```

Output:

```txt
Server: Running on http://localhost:8080
Server: Begin request http://localhost:8080/upload
Server: contentDisposition: form-data; name="file"; filename="__my__file.txt"
Server: Received: 131072 (+131072)
Server: Received: 196608 (+65536)
Server: Received: 262144 (+65536)
Server: Received: 393216 (+131072)
Server: Received: 458752 (+65536)
Server: Received: 589824 (+131072)
Client: Canceling
Client: Error: TaskCanceledException
Server: Exception HttpException: Connection closed while receiving data, uri = /upload
Server: End request http://localhost:8080/upload
```
