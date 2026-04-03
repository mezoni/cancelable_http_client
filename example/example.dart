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
