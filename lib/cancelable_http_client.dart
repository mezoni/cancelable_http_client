import 'dart:async';

import 'package:http/http.dart';
import 'package:multitasking/misc/pause.dart';
import 'package:multitasking/multitasking.dart';

export 'package:multitasking/multitasking.dart'
    show
        CancellationException,
        CancellationToken,
        CancellationTokenSource,
        StreamExtension;

/// A [CancelableClient] is a wrapper over [Client] that allows to cancel both a
/// request and the operation of receiving data from the response stream.
///
/// A cancelable client is a combination of [Client] and [CancellationToken].\
/// When a cancellation requested, the token cancels either the request
/// (receiving a response) or receiving data from the response stream.
///
/// If a cancellation occurs, the [CancellationException] exception is thrown.
///
/// Request cancellation is implemented by ignoring the cancelled connection
/// establishment.
///
/// Cancellation of the receiving of data from a response is implemented by
/// unsubscribing from the stream.
///
/// This client can be shared and it can be used repeatedly as long as it is not
/// closed.
class CancelableClient with BaseClient {
  final Client _client;

  final PauseToken? _pauseToken;

  final Duration? _requestTimeout;

  final Duration? _responseTimeout;

  final CancellationToken _token;

  /// Creates an instance of [CancelableClient].\
  ///
  /// Parameters:
  ///
  /// - [pauseToken]: Token for pausing and resuming data retrieval from the
  /// server.
  /// - [requestTimeout]: Time limit for waiting for a response from the server.
  /// - [responseTimeout: Time limit for waiting for data to be received from
  /// the server (maximum allowed delay between `onData` events).
  /// - [token]: Cancellation token to signal a cancellation request.
  CancelableClient(
    CancellationToken token, {
    PauseToken? pauseToken,
    Duration? requestTimeout,
    Duration? responseTimeout,
  })  : _client = Client(),
        _pauseToken = pauseToken,
        _requestTimeout = requestTimeout,
        _responseTimeout = responseTimeout,
        _token = token;

  @override
  void close() {
    _client.close();
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    _token.throwIfCanceled();
    final task = Task.run(() => _client.send(request));
    final tasks = [task.withCancellation(_token)];
    Timer? timer;
    if (_requestTimeout != null) {
      final completer = TaskCompletionSource<StreamedResponse>();
      timer = Timer(_requestTimeout!, () {
        completer.setError(TimeoutException(''), StackTrace.current);
      });

      tasks.add(completer.task);
    }

    Future<void> cancelRequest() async {
      try {
        // Wait for a response from the server.
        final response = await task;
        final stream = response.stream;
        // Notify the server to cancel the data transfer.
        await stream.listen(null).cancel();
      } catch (e) {
        // Ignore exception
      }
    }

    StreamedResponse response;
    try {
      response = await Future.any(tasks);
    } on CancellationException {
      timer?.cancel();
      unawaited(cancelRequest());
      rethrow;
    } on TimeoutException {
      unawaited(cancelRequest());
      rethrow;
    } finally {
      timer?.cancel();
    }

    final stream = response.stream;
    var cancelableStream = stream.asCancelable(
      _token,
      timeout: _responseTimeout,
    );

    if (_pauseToken != null) {
      cancelableStream = cancelableStream.asPausable(_pauseToken!);
    }

    return StreamedResponse(
      cancelableStream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
