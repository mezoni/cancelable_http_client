import 'dart:async';

import 'package:http/http.dart';
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

  final CancellationToken _token;

  /// Creates an instance of [CancelableClient].\
  ///
  /// Parameters:
  ///
  /// - [token]: Cancellation token to signal a cancellation request.
  CancelableClient(CancellationToken token)
      : _client = Client(),
        _token = token;

  @override
  void close() {
    _client.close();
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    _token.throwIfCanceled();
    final task = Task.run(() => _client.send(request));
    StreamedResponse response;
    try {
      response = await task.withCancellation(_token);
    } on CancellationException {
      // Ignore the cancelled operation.
      unawaited(() async {
        try {
          // Wait for a response from the server.
          final response = await task;
          final stream = response.stream;
          // Notify the server to cancel the data transfer.
          await stream.listen(null).cancel();
        } catch (e) {
          // Ignore exception
        }
      }());

      rethrow;
    }

    final stream = response.stream;
    final cancelableStream = stream.asCancelable(_token);
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
