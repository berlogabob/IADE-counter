import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iade_counter/sync.dart';

void main() {
  test('httpDateToEpoch parses the server date', () {
    expect(
      Sync.httpDateToEpoch('Tue, 13 Oct 2026 16:03:27 GMT'),
      DateTime.utc(2026, 10, 13, 16, 3, 27).millisecondsSinceEpoch,
    );
  });

  test('httpDateToEpoch parses the RFC example', () {
    expect(
      Sync.httpDateToEpoch('Sun, 06 Nov 1994 08:49:37 GMT'),
      DateTime.utc(1994, 11, 6, 8, 49, 37).millisecondsSinceEpoch,
    );
  });

  test('httpDateToEpoch rejects unparseable input', () {
    expect(Sync.httpDateToEpoch('garbage'), -1);
    expect(Sync.httpDateToEpoch('Tue, 13 Oct 2026 16:03 GMT'), -1);
    expect(Sync.httpDateToEpoch('Tue, 13 Oct 2026 16:xx:27 GMT'), -1);
  });

  test('poll applies the server clock offset', () async {
    final s = Sync(
      't',
      client: MockClient(
        (_) async => http.Response(
          '{}',
          200,
          headers: {'date': 'Tue, 13 Oct 2026 16:03:27 GMT'},
        ),
      ),
    );
    await s.poll();
    final expected =
        DateTime.utc(2026, 10, 13, 16, 3, 27).millisecondsSinceEpoch -
        DateTime.now().millisecondsSinceEpoch;
    expect(s.offsetMs, closeTo(expected, 2000));
  });
}
