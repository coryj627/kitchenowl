// Picked up by `flutter test` for the test files under test/a11y/ only (the
// nearest flutter_test_config.dart wins; the app has none of its own, so its
// other tests run exactly as before).  It adds what the accessibility audit
// needs: the findings sink, the per-screen log, and real fonts.
import 'dart:async';

import 'package:flutter_a11y_test/flutter_a11y_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Writes .a11y/flutter/runtime-findings.json, which
  // `a11y_check_flutter scan` merges into its report.
  RuntimeFindingsSink.configure();
  tearDownAll(RuntimeFindingsSink.flush);
  tearDownAll(ScreenLog.flush);

  TestWidgetsFlutterBinding.ensureInitialized();
  await loadRealFonts();

  await testMain();
}
