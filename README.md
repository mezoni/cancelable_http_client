# cancelable_http_client

A cancelable HTTP client is a wrapper over `http.Client` that allows to cancel a request or the operation of receiving data from the response or sending data via request.

Version: 2.3.0

[![Pub Package](https://img.shields.io/pub/v/cancelable_http_client.svg)](https://pub.dev/packages/cancelable_http_client)
[![Pub Monthly Downloads](https://img.shields.io/pub/dm/cancelable_http_client.svg)](https://pub.dev/packages/cancelable_http_client/score)
[![GitHub Issues](https://img.shields.io/github/issues/mezoni/cancelable_http_client.svg)](https://github.com/mezoni/cancelable_http_client/issues)
[![GitHub Forks](https://img.shields.io/github/forks/mezoni/cancelable_http_client.svg)](https://github.com/mezoni/cancelable_http_client/forks)
[![GitHub Stars](https://img.shields.io/github/stars/mezoni/cancelable_http_client.svg)](https://github.com/mezoni/cancelable_http_client/stargazers)
[![GitHub License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://raw.githubusercontent.com/mezoni/cancelable_http_client/main/LICENSE)

## About this software

This software is a small library that implements the ability to cancel HTTP operations using a [Client](https://pub.dev/documentation/http/latest/http/Client-class.html) from the [http](https://pub.dev/packages/http) package.  
This is implemented using a composition of class [Client](https://pub.dev/documentation/http/latest/http/Client-class.html) and class [CancellationToken](https://pub.dev/documentation/multitasking/latest/multitasking/CancellationToken-class.html).  
When a cancellation request is performed, the token cancels the HTTP operation.

The result of the cancellation is the exception [CancellationException](https://pub.dev/documentation/multitasking/latest/multitasking/CancellationException-class.html), which indicates that the operation did not complete successfully.

Canceling an HTTP operation on the client does not mean cancelling the operation on the server.  

Client-side cancellation allows to automatically cancel the following actions:

- Receiving data from the server on the client
- Sending data from the client on the server
- (If necessary) Any action on the client that can be interrupted by throwing an exception (using `token.throwIfCanceled()`)

Canceling an HTTP operation, do not close the client. If closing a client is mandatory (according to convention), then it must be explicitly closed using the `close()` method.  
The client prevents a request from being sent if a cancellation request has already been made previously.  

The operating algorithm is as follows.

**Receiving data from the server**.  
If a cancellation request is initiated before a response is received from the server, the response is ignored and the operation of receiving data from the server is cancelled immediately after receiving a response.  
If a cancellation request is initiated after a response is received from the server, the operation to receive data from the server is canceled immediately.  

**Sending multipart data to the server.**  
Before sending a request, the client prepares the data to be sent.  
Data transfer is performed through streams for each part independently.  
These streams must be submitted to the request as [cancelable](https://pub.dev/documentation/multitasking/latest/multitasking/StreamExtension/asCancelable.html) streams (that is, supporting the cancel operation and throwing the  `CancellationException` exception).  
Initiating a cancellation request cancels the sending of data through these streams.

**Additional features:**

- Pausing and resuming data reception using a pause token
- Canceling a request before receiving data using the `requestTimeout` parameter
- Canceling data retrieval using the `responseTimeout` parameter

## Example of canceling 'GET' request

[example/example_cancel_get_request.dart](https://github.com/mezoni/cancelable_http_client/blob/main/example/example_cancel_get_request.dart)

```dart
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

```

Output:

```txt
Client: Send request with timeout 3000 ms
Server: Begin request: http://localhost:8080/
Client: Error: CancellationException at 3009 ms
Client: Elapsed 3009 ms
Server: End request: http://localhost:8080/

```

## Example of canceling 'GET' request using `requestTimeout` parameter

[example/example_cancel_get_request_using_request_timeout.dart](https://github.com/mezoni/cancelable_http_client/blob/main/example/example_cancel_get_request_using_request_timeout.dart)

```dart
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
        _server('Request delay 5 sec');
        await Future<void>.delayed(Duration(seconds: 5));
        response.add([1, 2, 3]);
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
  final cts = CancellationTokenSource();
  final token = cts.token;
  final client = CancelableClient(
    token,
    requestTimeout: Duration(milliseconds: timeout),
  );
  try {
    _client('Send request with request timeout $timeout ms');
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

```

Output:

```txt
Client: Send request with request timeout 3000 ms
Server: Begin request: http://localhost:8080/
Server: Request delay 5 sec
Client: Error: TimeoutException:  at 3044 ms
Client: Elapsed 3045 ms
Server: End request: http://localhost:8080/

```

## Example of canceling 'GET' request using `responseTimeout` parameter

[example/example_cancel_get_request_using_response_timeout.dart](https://github.com/mezoni/cancelable_http_client/blob/main/example/example_cancel_get_request_using_response_timeout.dart)

```dart
import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';
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
  const timeout = 2000;
  final watch = Stopwatch()..start();
  final cts = CancellationTokenSource();
  final token = cts.token;
  final client = CancelableClient(
    token,
    responseTimeout: Duration(seconds: 2),
  );
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
        _server('Request delay 3 sec');
        await Future<void>.delayed(Duration(seconds: 3));
        await for (final event in stream) {
          sent += event.length;
          _server('Send data with delay $delay sec');
          await Future<void>.delayed(Duration(seconds: delay++));
          yield event;
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

```

Output:

```txt
Client: Creating a temporary file
Client: Temp file size: 327.68 MB
Serving at http://localhost:8080
Client: Send request with response timeout 2000 ms
2026-05-17T18:28:29.814422  0:00:00.018284 GET     [200] /test_file.txt
Server: Request delay 3 sec
Server: Send data with delay 0 sec
Server: Send data with delay 1 sec
Server: Send data with delay 2 sec
Client: Error: TimeoutException at 6145 ms
Client: Elapsed 6145 ms
Server: Send data with delay 3 sec
Client: Deleting a temporary file
Server: Canceled: Sent: 0.26 MB

```

## Example of receiving data using the `GET` method

[example/example.dart](https://github.com/mezoni/cancelable_http_client/blob/main/example/example.dart)

```dart
import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';
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
  const timeout = 250;
  final watch = Stopwatch()..start();
  final cts = CancellationTokenSource(Duration(milliseconds: timeout));
  final token = cts.token;
  final client = CancelableClient(token);
  try {
    _client('Send request with timeout $timeout ms');
    final response = await client.get(url);
    cts.cancelAfter(null);
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
      var state = 'Canceled';
      var sent = 0;
      try {
        await for (final event in stream) {
          sent += event.length;
          yield event;
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

```

Output:

```txt
Client: Creating a temporary file
Client: Temp file size: 327.68 MB
Serving at http://localhost:8080
Client: Send request with timeout 250 ms
2026-05-17T18:28:44.568318  0:00:00.021840 GET     [200] /test_file.txt
Client: Error: CancellationException at 259 ms
Client: Elapsed 259 ms
Server: Canceled: Sent: 10.42 MB
Client: Deleting a temporary file

```

## Example of sending multipart data using the `POST` method

[example/example_multipart_request.dart](https://github.com/mezoni/cancelable_http_client/blob/main/example/example_multipart_request.dart)

```dart
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
    final request = MultipartRequest("POST", url);
    final file = File(filepath);
    // Make it possible to cancel sending data.
    final stream = file.openRead().asCancelable(token);
    request.files.add(MultipartFile('file', stream, file.lengthSync()));
    request.headers['Content-Type'] = 'text/plain';
    _client('Sending multipart request with timeout $timeout ms');
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

```

Output:

```txt
Client: Creating a temporary file
Client: Temp file size: 327.68 MB
Client: Sending multipart request with timeout 250 ms
Server: Begin request: http://localhost:8080/
Client: Error: CancellationException at 259 ms
Client: Elapsed 259 ms
Server: Received: 19.53 MB
Server: Error: HttpException: Connection closed while receiving data, uri = /
Server: End request: http://localhost:8080/

```

## Example of sending streamed data using the `POST` method

[example/example_streamed_request.dart](https://github.com/mezoni/cancelable_http_client/blob/main/example/example_streamed_request.dart)

```dart
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

```

Output:

```txt
Client: Creating a temporary file
Client: Temp file size: 327.68 MB
Client: Sending streaming request with timeout 250 ms
Server: Begin request: http://localhost:8080/
Client: Error: CancellationException at 258 ms
Client: Elapsed 259 ms
Server: Received: 24.97 MB
Server: Error: HttpException: Connection closed while receiving data, uri = /
Server: End request: http://localhost:8080/

```

## Example of pausing data retrieval using the `GET` method

[example/example_pause_get_request.dart](https://github.com/mezoni/cancelable_http_client/blob/main/example/example_pause_get_request.dart)

```dart
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

```

Output:

```txt
Client: Creating a temporary file
Client: Temp file size: 327.68 MB
Serving at http://localhost:8080
Client: Send request with response timeout 5500 ms
2026-05-17T18:29:13.966317  0:00:00.020501 GET     [200] /test_file.txt
Server: Delay 0 sec
Server: Delay 1 sec
Server: Delay 2 sec
Client: Pause 6 sec, longer than timeout
Server: Delay 3 sec
Server: Delay 4 sec
Client: Resume aster 6 sec
Server: Delay 5 sec
Server: Delay 6 sec
Client: Error: TimeoutException at 23664 ms
Client: Elapsed 23664 ms
Server: Delay 7 sec
Client: Deleting a temporary file
Server: Canceled: Sent: 0.52 MB

```
