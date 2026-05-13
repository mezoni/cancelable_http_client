import 'dart:async';
import 'dart:io';

import 'package:cancelable_http_client/cancelable_http_client.dart';
import 'package:http/http.dart';
import 'package:multitasking/misc/pause.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

void main() {
  _testClient();
}

void _testClient() {
  test('Client: cancel after timeout', () async {
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

    expect(error, isA<CancellationException>(), reason: 'error');
    expect(clock.elapsedMilliseconds, lessThan(10000),
        reason: 'elapsedMilliseconds');
    expect(serverPrologue, isTrue, reason: 'serverPrologue');
    expect(serverEpilogue, isFalse, reason: 'serverEpilogue');
    await server.close();
  });

  test('Client: cancel using requestTimeout', () async {
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

    final cts = CancellationTokenSource();
    final token = cts.token;
    final client = CancelableClient(
      token,
      requestTimeout: Duration(seconds: 3),
    );
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

    expect(error, isA<TimeoutException>(), reason: 'error');
    expect(clock.elapsedMilliseconds, lessThan(10000),
        reason: 'elapsedMilliseconds');
    expect(serverPrologue, isTrue, reason: 'serverPrologue');
    expect(serverEpilogue, isFalse, reason: 'serverEpilogue');
    await server.close();
  });

  test('cancel using responseTimeout', () async {
    final server = await HttpServer.bind('localhost', 8080);
    final serverUrl = 'http://${server.address.host}:${server.port}';

    var serverPrologue = false;
    var serverSendingData = false;
    var serverEpilogue = false;
    var serverReturns = false;
    unawaited(() async {
      await for (HttpRequest request in server) {
        final response = request.response;
        try {
          response.bufferOutput = false;
          serverPrologue = true;
          await Future<void>.delayed(Duration(seconds: 5));
          // sink.close() ignore
          // ignore: close_sinks
          final controller = StreamController<List<int>>();
          var isCanceled = false;
          controller.onListen = () {
            unawaited(() async {
              for (var i = 0; i < 10; i++) {
                serverSendingData = true;
                if (isCanceled) {
                  break;
                }

                controller.add([i]);
                await Future<void>.delayed(Duration(seconds: i));
              }
            }());
          };
          controller.onCancel = () {
            isCanceled = true;
          };

          await response.addStream(controller.stream);
          serverEpilogue = true;
        } catch (e) {
          //
        } finally {
          serverReturns = true;
          await response.close();
        }
      }
    }());

    final cts = CancellationTokenSource();
    final token = cts.token;
    final client = CancelableClient(
      token,
      responseTimeout: Duration(seconds: 2),
    );
    Object? error;
    try {
      await client.get(Uri.parse(serverUrl));
    } catch (e) {
      error = e;
    }

    expect(error, isA<TimeoutException>(), reason: 'error');
    expect(serverPrologue, isTrue, reason: 'serverPrologue');
    expect(serverSendingData, isTrue, reason: 'serverSendingData');
    expect(serverEpilogue, isFalse, reason: 'serverEpilogue');
    await Future<void>.delayed(Duration(seconds: 2));
    expect(serverEpilogue, isTrue, reason: 'serverEpilogue');
    expect(serverReturns, isTrue, reason: 'serverReturns');
    await server.close();
  });

  test('pause using pauseToken', () async {
    final server = await HttpServer.bind('localhost', 8080);
    final serverUrl = 'http://${server.address.host}:${server.port}';

    var serverPrologue = false;
    var serverSendingData = false;
    var serverEpilogue = false;
    var serverReturns = false;
    unawaited(() async {
      await for (HttpRequest request in server) {
        final response = request.response;
        try {
          response.bufferOutput = false;
          serverPrologue = true;
          final stream = Stream.periodic(Duration(milliseconds: 500), (i) {
            serverSendingData = true;
            return [i];
          });
          await response.addStream(stream);
          serverEpilogue = true;
        } catch (e) {
          //
        } finally {
          serverReturns = true;
          await response.close();
        }
      }
    }());

    final cts = CancellationTokenSource();
    final token = cts.token;
    final pts = PauseTokenSource();
    final pauseToken = pts.token;
    final client = CancelableClient(
      token,
      pauseToken: pauseToken,
      responseTimeout: Duration(seconds: 1),
    );

    var count = 0;
    var count2 = 0;
    Timer(Duration(seconds: 2), () async {
      expect(count, greaterThan(0), reason: 'count');
      await pts.pause();
      count2 = count;
    });

    Timer(Duration(seconds: 5), () async {
      expect(count, equals(count2), reason: 'count');
      await pts.resume();
    });

    Timer(Duration(seconds: 8), () async {
      expect(count, greaterThan(count2), reason: 'count');
      cts.cancel();
    });

    Object? error;
    try {
      //await client.get(Uri.parse(serverUrl));
      final request = Request('GET', Uri.parse(serverUrl));
      final response = await client.send(request);
      await for (final _ in response.stream) {
        count++;
      }
    } catch (e) {
      error = e;
    }

    expect(error, isA<CancellationException>(), reason: 'error');
    expect(serverPrologue, isTrue, reason: 'serverPrologue');
    expect(serverSendingData, isTrue, reason: 'serverSendingData');
    expect(serverEpilogue, isFalse, reason: 'serverEpilogue');
    await Future<void>.delayed(Duration(seconds: 2));
    expect(serverEpilogue, isTrue, reason: 'serverEpilogue');
    expect(serverReturns, isTrue, reason: 'serverReturns');
    await server.close();
  });

  test('Client: GET', () async {
    final server = await HttpServer.bind('localhost', 8080);
    final serverUrl = 'http://${server.address.host}:${server.port}';

    var serverPrologue = false;
    var serverSendingData = false;
    var serverEpilogue = false;
    var serverReturns = false;
    unawaited(() async {
      await for (HttpRequest request in server) {
        final response = request.response;
        try {
          response.bufferOutput = false;
          serverPrologue = true;
          final stream = Stream.periodic(Duration(milliseconds: 500), (i) {
            serverSendingData = true;
            return [i];
          });
          await response.addStream(stream);
          serverEpilogue = true;
        } catch (e) {
          //
        } finally {
          serverReturns = true;
          await response.close();
        }
      }
    }());

    final cts = CancellationTokenSource(Duration(seconds: 1));
    final token = cts.token;
    final client = CancelableClient(token);
    Object? error;
    try {
      await client.get(Uri.parse(serverUrl));
    } catch (e) {
      error = e;
    }

    expect(error, isA<CancellationException>(), reason: 'error');
    expect(serverPrologue, isTrue, reason: 'serverPrologue');
    expect(serverSendingData, isTrue, reason: 'serverSendingData');
    expect(serverEpilogue, isFalse, reason: 'serverEpilogue');
    await Future<void>.delayed(Duration(seconds: 2));
    expect(serverEpilogue, isTrue, reason: 'serverEpilogue');
    expect(serverReturns, isTrue, reason: 'serverReturns');
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
          await for (final _ in request) {
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
    Object? error;

    var clientSendingData = false;
    try {
      final request = MultipartRequest("POST", Uri.parse(serverUrl));
      final data = List.filled(256 * 256, 0);
      final stream = Stream.periodic(Duration(milliseconds: 1), (_) {
        clientSendingData = true;
        return data;
      });

      final file =
          MultipartFile('file', stream.asCancelable(token), 0xffffffff);
      request.files.add(file);
      await client.send(request);
    } catch (e) {
      error = e;
    }

    expect(error, isA<CancellationException>(), reason: 'error');
    expect(clientSendingData, isTrue, reason: 'clientSendingData');
    expect(serverPrologue, isTrue, reason: 'serverPrologue');
    expect(serverReceivingData, isTrue, reason: 'serverReceivingData');
    await Future<void>.delayed(Duration(seconds: 1));
    expect(serverEpilogue, isFalse, reason: 'serverEpilogue');
    expect(serverError, isA<HttpException>(), reason: 'serverError');
    await server.close();
  });
}
