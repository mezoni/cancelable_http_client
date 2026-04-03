import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';
import 'package:http/http.dart';
import 'package:multitasking/multitasking.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

void main() {
  _testClient();
}

void _testClient() {
  test('Client: Timeout', () async {
    final server = await HttpServer.bind('localhost', 8080);
    final serverUrl = 'http://${server.address.host}:${server.port}';

    var serverPrologue = false;
    var serverEpilogue = false;
    unawaited(() async {
      await for (HttpRequest request in server) {
        final response = request.response;
        try {
          serverPrologue = true;
          await Future<void>.delayed(Duration(seconds: 10));
          serverEpilogue = true;
        } catch (e) {
          //
        } finally {
          await response.close();
        }
      }
    }());

    final cts = CancellationTokenSource(Duration(seconds: 3));
    final token = cts.token;
    final client = CancelableClient(token);
    final clock = Stopwatch();
    Object? error;

    try {
      final request = Request("GET", Uri.parse(serverUrl));
      clock.start();
      await client.send(request);
    } catch (e) {
      clock.stop();
      error = e;
    }

    expect(error, isA<TaskCanceledException>(), reason: 'exception');
    expect(clock.elapsedMilliseconds, lessThan(10000),
        reason: 'elapsedMilliseconds');
    expect(serverPrologue, true, reason: 'serverPrologue');
    expect(serverEpilogue, false, reason: 'serverEpilogue');
    await server.close();
  });

  test('Client: GET', () async {
    final server = await HttpServer.bind('localhost', 8080);
    final serverUrl = 'http://${server.address.host}:${server.port}';

    var serverPrologue = false;
    var serverEpilogue = false;
    unawaited(() async {
      await for (HttpRequest request in server) {
        final response = request.response;
        try {
          serverPrologue = true;
          final stream = Stream.periodic(Duration(milliseconds: 1), (_) {
            return [0];
          });
          await response.addStream(stream);
          serverEpilogue = true;
        } catch (e) {
          //
        } finally {
          await response.close();
        }
      }
    }());

    final cts = CancellationTokenSource(Duration(seconds: 3));
    final token = cts.token;
    final client = CancelableClient(token);
    final clock = Stopwatch();
    Object? error;

    try {
      clock.start();
      await client.get(Uri.parse(serverUrl));
    } catch (e) {
      clock.stop();
      error = e;
    }

    expect(error, isA<TaskCanceledException>(), reason: 'exception');
    expect(serverPrologue, true, reason: 'serverPrologue');
    expect(serverEpilogue, false, reason: 'serverEpilogue');
    await Future<void>.delayed(Duration(seconds: 1));
    expect(serverEpilogue, true, reason: 'serverEpilogue');
    await server.close();
  });

  test('Client: POST (multipart)', () async {
    final server = await HttpServer.bind('localhost', 8080);
    final serverUrl = 'http://${server.address.host}:${server.port}';

    var serverPrologue = false;
    var serverReceivingData = false;
    var serverEpilogue = false;
    Object? serverError;
    unawaited(() async {
      await for (HttpRequest request in server) {
        final response = request.response;
        try {
          serverPrologue = true;
          // Unused
          // ignore: unused_local_variable
          await for (final event in request) {
            serverReceivingData = true;
          }

          serverEpilogue = true;
        } catch (e) {
          serverError = e;
        } finally {
          await response.close();
        }
      }
    }());

    final cts = CancellationTokenSource(Duration(seconds: 3));
    final token = cts.token;
    final client = CancelableClient(token);
    final clock = Stopwatch();
    Object? error;

    var clientSendingData = false;
    try {
      clock.start();
      final request = MultipartRequest("POST", Uri.parse(serverUrl));
      final data = List.filled(256 * 256, 0);
      final stream = Stream.periodic(Duration(milliseconds: 1), (_) {
        clientSendingData = true;
        return data;
      });

      final file = MultipartFile('file',
          stream.asCancelable(token, throwIfCanceled: true), 0xffffffff);
      request.files.add(file);
      await client.send(request);
    } catch (e) {
      clock.stop();
      error = e;
    }

    expect(error, isA<TaskCanceledException>(), reason: 'exception');
    expect(clientSendingData, true, reason: 'clientSendingData');
    expect(serverPrologue, true, reason: 'serverPrologue');
    expect(serverReceivingData, true, reason: 'serverReceivingData');
    await Future<void>.delayed(Duration(seconds: 1));
    expect(serverEpilogue, false, reason: 'serverEpilogue');
    expect(serverError, isA<HttpException>(), reason: 'serverError');
    await server.close();
  });
}
