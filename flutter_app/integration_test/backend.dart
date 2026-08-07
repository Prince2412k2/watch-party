import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fail the calling test unless a backend is answering at [base].
///
/// The tests in this directory used to probe the backend and, when it was
/// missing, call `markTestSkipped` and return — which meant they reported
/// success-with-a-skip in every environment that has ever run them, including
/// CI. They are now opt-in (nothing runs `integration_test/` by accident), so an
/// unreachable backend is a real failure: you asked for these tests, and they
/// could not do their job.
Future<void> requireBackend(String base) async {
  try {
    final probe = await HttpClient()
        .getUrl(Uri.parse('$base/api/health'))
        .then((request) => request.close())
        .timeout(const Duration(seconds: 2));
    if (probe.statusCode != 200) {
      fail('backend at $base answered /api/health with ${probe.statusCode}, expected 200');
    }
  } on Object catch (error) {
    fail(
      'backend not reachable at $base ($error).\n'
      'These are live integration tests — start the dev server first, or point '
      'them elsewhere with --dart-define=API_BASE=<url>. See integration_test/README.md.',
    );
  }
}
