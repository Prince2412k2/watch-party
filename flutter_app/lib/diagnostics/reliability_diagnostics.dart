import 'dart:collection';
import 'dart:convert';

class ReliabilityDiagnostics {
  ReliabilityDiagnostics({this.capacity = 512, Stopwatch? clock})
    : assert(capacity > 0),
      _clock = clock ?? (Stopwatch()..start());

  static final instance = ReliabilityDiagnostics();

  final int capacity;
  final Stopwatch _clock;
  final Queue<Map<String, Object?>> _records = Queue();

  void record(String scope, String event, Map<String, Object?> fields) {
    if (_records.length == capacity) _records.removeFirst();
    _records.addLast({
      'elapsedMs': _clock.elapsedMilliseconds,
      'scope': scope,
      'event': event,
      ...fields,
    });
  }

  List<Map<String, Object?>> snapshot() => _records
      .map((record) => Map<String, Object?>.unmodifiable(record))
      .toList(growable: false);

  String exportJson() =>
      jsonEncode({'schemaVersion': 1, 'records': snapshot()});

  void clear() => _records.clear();
}
