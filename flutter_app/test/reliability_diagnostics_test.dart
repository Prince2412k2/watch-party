import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/diagnostics/reliability_diagnostics.dart';

void main() {
  test('diagnostics are bounded, ordered, and JSON exportable', () {
    final diagnostics = ReliabilityDiagnostics(capacity: 2);
    diagnostics.record('sync', 'first', {'positionMs': 1});
    diagnostics.record('sync', 'second', {'positionMs': 2});
    diagnostics.record('media-cache', 'third', {'item': 'redacted-hash'});

    final records = diagnostics.snapshot();
    expect(records.map((record) => record['event']), ['second', 'third']);
    expect(records[0]['elapsedMs'], isA<int>());
    expect(
      records[1]['elapsedMs'] as int,
      greaterThanOrEqualTo(records[0]['elapsedMs'] as int),
    );

    final exported =
        jsonDecode(diagnostics.exportJson()) as Map<String, dynamic>;
    expect(exported['schemaVersion'], 1);
    expect(exported['records'], hasLength(2));
    expect(diagnostics.exportJson(), isNot(contains('signed-token')));
  });
}
