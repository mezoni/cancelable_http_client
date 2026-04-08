# cancelable_http_client

A cancelable HTTP client is a wrapper over `http.Client` that allows to cancel a request or the operation of receiving data from the response or sending data via request.

Version: 1.1.5

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

The result of the cancellation is the exception [TaskCanceledException](https://pub.dev/documentation/multitasking/latest/multitasking/TaskCanceledException-class.html), which indicates that the operation did not complete successfully.

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
These streams must be submitted to the request as [cancelable](https://pub.dev/documentation/multitasking/latest/multitasking/StreamExtension/asCancelable.html) streams (that is, supporting the cancel operation and throwing the  `TaskCanceledException` exception).  
Initiating a cancellation request cancels the sending of data through these streams.

## Example timeout

```dart
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
        await Future<void>.delayed(Duration(seconds: 5));
      } catch (e) {
        _server('Error: $e');
      } finally {
        _server('End request: $url');
        await response.close();
      }
    }
  }());

  final url = Uri.parse(serverUrl);
  const timeout = 3000;
  final watch = Stopwatch();
  watch.start();
  final cts = CancellationTokenSource(Duration(milliseconds: timeout));
  final token = cts.token;
  final client = CancelableClient(token);
  try {
    _client('Send request with timeout $timeout ms');
    await client.get(url);
    _client('Received response');
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

```

Output:

```txt
Client: Send request with timeout 3000 ms
Server: Begin request: http://localhost:8080/
Client: Error: TaskCanceledException at 3009
Client: Elapsed 3009 ms
Server: End request: http://localhost:8080/
```

## Example receiving data

```dart
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

```

Output:

```txt
Client: Send request with timeout 2500 ms
Server: Begin request: http://localhost:8080/
Server: Total chunks: 100
Server: Send chunk: 0
Server: Send chunk: 1
Server: Send chunk: 2
Client: Error: TaskCanceledException at 2516
Client: Elapsed 2516 ms
Server: Send chunk: 3
Server: End request: http://localhost:8080/
Server: Total number of chunks sent: 3 of 100
```

## Example sending data

```dart
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
      final url = request.requestedUri;
      _server('Begin request: $url');
      try {
        var count = 0;
        await for (final _ in request) {
          _server('Received chunk: $count');
          count++;
        }

        _server('Received data');
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
    final request = MultipartRequest("POST", url);
    const partSize = 65536;
    const count = 100;
    final part = List.filled(partSize, 48);
    Stream<List<int>> gen() async* {
      const count = 100;
      _client('Total chunks: $count');
      for (var i = 0; i < count; i++) {
        _client('Send chunk: $i');
        yield part;
        await Future<void>.delayed(Duration(seconds: 1));
      }
    }

    const fileSize = partSize * count;
    final file = MultipartFile(
      'file',
      gen().asCancelable(token, throwIfCanceled: true),
      fileSize,
    );
    request.files.add(file);
    _client('Sending multipart request with timeout $timeout ms');
    await client.send(request);
    _client('Received response');
  } catch (e) {
    _client('Error: $e');
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
Client: Sending multipart request with timeout 2500 ms
Client: Total chunks: 100
Client: Send chunk: 0
Server: Begin request: http://localhost:8080/
Server: Received chunk: 0
Client: Send chunk: 1
Server: Received chunk: 1
Client: Send chunk: 2
Server: Received chunk: 2
Client: Error: TaskCanceledException
Client: Elapsed 2507 ms
Server: Error: HttpException: Connection closed while receiving data, uri = /
Server: End request: http://localhost:8080/
Client: Send chunk: 3
```
