# cancelable_http_client

A cancelable HTTP client is a wrapper over `http.Client` that allows to cancel a request or the operation of receiving data from the response or sending data via request.

Version: 1.1.4

[![Pub Package](https://img.shields.io/pub/v/cancelable_http_client.svg)](https://pub.dev/packages/cancelable_http_client)
[![Pub Monthly Downloads](https://img.shields.io/pub/dm/cancelable_http_client.svg)](https://pub.dev/packages/cancelable_http_client/score)
[![GitHub Issues](https://img.shields.io/github/issues/mezoni/cancelable_http_client.svg)](https://github.com/mezoni/cancelable_http_client/issues)
[![GitHub Forks](https://img.shields.io/github/forks/mezoni/cancelable_http_client.svg)](https://github.com/mezoni/cancelable_http_client/forks)
[![GitHub Stars](https://img.shields.io/github/stars/mezoni/cancelable_http_client.svg)](https://github.com/mezoni/cancelable_http_client/stargazers)
[![GitHub License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://raw.githubusercontent.com/mezoni/cancelable_http_client/main/LICENSE)

## About this software

This software is a small library that implements the ability to cancel HTTP operations using a [Client](https://pub.dev/documentation/http/latest/http/Client-class.html) from the [http](https://pub.dev/packages/http) package.  
This is implemented using a composition of class [Client](https://pub.dev/documentation/http/latest/http/Client-class.html) and class [CancellationToken](https://pub.dev/documentation/multitasking/latest/multitasking/CancellationToken-class.html).  
When a cancellation request is made, the token cancels the HTTP operation.

The result of the cancellation is the exception [TaskCanceledException](https://pub.dev/documentation/multitasking/latest/multitasking/TaskCanceledException-class.html), which indicates that the operation did not complete successfully.

Canceling an HTTP operation on the client does not mean cancelling the operation on the server.  

Client-side cancellation allows to automatically cancel the following actions:

- Receiving data from the server on the client
- Sending data from the client on the server
- (If necessary) Any action on the client that can be interrupted by throwing an exception (using `token.throwIfCanceled()`)

Cancel operations do not close the client. If necessary, it must be closed forcibly.  
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

```

Output:

```txt
Client: Sending multipart request
Server: Receiving request
Server: Begin operation
Client: Sending data
Server: Receiving data
Client: Sending data
Server: Receiving data
Client: Error: TaskCanceledException
Client: Done
Server: Error: HttpException: Connection closed while receiving data, uri = /
Server: Send response
Client: Shuting down a server
```
