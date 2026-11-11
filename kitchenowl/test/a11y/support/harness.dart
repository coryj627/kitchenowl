/// Shared plumbing for the accessibility audit in `screens_a11y_test.dart`:
/// real fonts, the two viewports, growing the view over lazy lists, the audit
/// call itself, and the per-screen log.
///
/// See `../README.md` for what each decision does to findings.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_a11y_test/flutter_a11y_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A window the app is audited in.
enum AuditViewport {
  /// A phone: 412x915 logical px at device pixel ratio 3.
  phone(Size(412, 915), 3),

  /// A desktop browser window: 1280x800 logical px at device pixel ratio 1.
  /// The app's responsive layout switches to its navigation rail here.
  wide(Size(1280, 800), 1);

  const AuditViewport(this.size, this.devicePixelRatio);

  final Size size;
  final double devicePixelRatio;

  /// `shopping-list` audited in this viewport is `shopping-list@phone`.
  String idFor(String screen) => '$screen@$name';
}

/// The tallest a view is ever grown to (logical px).
///
/// The contrast rules rasterize the whole view at its device pixel ratio;
/// this keeps that image under about 100 MB on the phone.
const double kMaxGrownHeight = 6000;

/// Where the per-screen log goes, next to the findings the sink writes.
const String kScreensLogPath = '.a11y/flutter/runtime-screens.json';

/// The audit configuration for every screen.
///
/// Library defaults, with both platform tap-target guidelines
/// (`platform: null`; the app ships on Android, iOS and the web), the reflow
/// passes on, and attribution restricted to the app's `lib/` so that a
/// finding is never attributed to this harness.
A11yAuditConfig get auditConfig => A11yAuditConfig(
      platform: null,
      reflow: true,
      sourceRoots: ['${Directory.current.path}/lib/'],
    );

/// Loads the fonts the app ships, plus the two Material fonts from the
/// Flutter SDK, so text is measured as on a device rather than in the
/// `FlutterTest` font (every glyph a 1 em square).
///
/// Set `A11Y_TEST_FONT=ahem` to skip this and compare with the default font.
Future<void> loadRealFonts() async {
  if (Platform.environment['A11Y_TEST_FONT'] == 'ahem') return;

  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) {
        throw StateError('a11y harness: font file missing: $path');
      }
      loader.addFont(
          file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  // The families declared under `flutter: fonts:` in pubspec.yaml.
  final pubspecFonts = _pubspecFonts();
  for (final MapEntry(key: family, value: assets) in pubspecFonts.entries) {
    await load(family, assets);
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError('a11y harness: FLUTTER_ROOT is not set');
  }
  final materialFonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  await load('MaterialIcons', ['$materialFonts/MaterialIcons-Regular.otf']);
  // Roboto is among the app's own fonts (all twelve styles), loaded above.
}

/// The visible text on screen whose style names no font family.
///
/// Such text is drawn in the platform's default font on a device (Roboto on
/// Android), but under `flutter test` in the engine's built-in test font,
/// where every glyph is a 1 em square, and nothing loaded at run time can
/// replace that default.  In this app it is every chip label: the app's chip
/// theme sets `labelStyle: TextStyle(color: ...)`, which replaces the text
/// theme's style instead of extending it.  The text is wider here than on a
/// device, so an overflow finding on it needs a second look.
List<String> textInTestFont(WidgetTester tester) {
  final result = <String>{};
  for (final element in find.byType(RichText).hitTestable().evaluate()) {
    final span = (element.widget as RichText).text;
    if (span is! TextSpan) continue;
    final style = span.style;
    if (style?.fontFamily != null ||
        (style?.fontFamilyFallback?.isNotEmpty ?? false)) {
      continue;
    }
    final text = span.toPlainText(includePlaceholders: false).trim();
    if (text.isNotEmpty) result.add(text);
  }
  return result.toList()..sort();
}

/// Family name to asset paths, read from the `fonts:` section of pubspec.yaml.
///
/// A small line-based reader, to avoid a YAML dependency: the section is a
/// list of `- family: X` entries each followed by `- asset: path` lines.
Map<String, List<String>> _pubspecFonts() {
  final result = <String, List<String>>{};
  String? family;
  var inFonts = false;
  for (final line in File('pubspec.yaml').readAsLinesSync()) {
    if (line == '  fonts:') {
      inFonts = true;
      continue;
    }
    if (!inFonts) continue;
    final familyMatch = RegExp(r'^\s+- family:\s*(.+?)\s*$').firstMatch(line);
    if (familyMatch != null) {
      family = familyMatch.group(1)!;
      result[family] = [];
      continue;
    }
    final assetMatch = RegExp(r'^\s+- asset:\s*(.+?)\s*$').firstMatch(line);
    if (assetMatch != null && family != null) {
      result[family]!.add(assetMatch.group(1)!);
    }
  }
  if (result.isEmpty) {
    throw StateError('a11y harness: no fonts found in pubspec.yaml');
  }
  return result;
}

/// Sets [viewport] on the view (not just the surface), so `MediaQuery` and
/// the audit's reflow pass both start from it.
void useViewport(WidgetTester tester, AuditViewport viewport) {
  tester.view.devicePixelRatio = viewport.devicePixelRatio;
  tester.view.physicalSize = viewport.size * viewport.devicePixelRatio;
  addTearDown(tester.view.reset);
}

/// How far the vertical scrollables on screen can still scroll, in total.
double remainingScrollPx(WidgetTester tester) {
  var total = 0.0;
  for (final element in find.byType(Scrollable).evaluate()) {
    final position = (element as StatefulElement).state as ScrollableState;
    final p = position.position;
    if (!p.hasContentDimensions || p.axis != Axis.vertical) continue;
    total += p.maxScrollExtent - p.minScrollExtent;
  }
  return total;
}

/// Grows the view's height until no vertical scrollable has anything left to
/// scroll, so a lazily built list is laid out (and audited) in full.
///
/// Stops at [kMaxGrownHeight], or when growing further changes nothing.
/// Returns the final logical size.
Future<Size> growViewToFit(WidgetTester tester) async {
  var size = tester.view.physicalSize / tester.view.devicePixelRatio;
  var remaining = remainingScrollPx(tester);
  for (var i = 0; i < 12; i++) {
    if (remaining <= 0.5 || size.height >= kMaxGrownHeight) break;
    final before = size;
    size = Size(size.width,
        (size.height + remaining).ceilToDouble().clamp(0, kMaxGrownHeight));
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final now = remainingScrollPx(tester);
    if (now >= remaining) {
      // Growing did not help: what is left does not depend on the height (a
      // NestedScrollView's header can always be scrolled away, however tall
      // the view).  Go back to the last height that made a difference.
      size = before;
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      break;
    }
    remaining = now;
  }
  return size;
}

/// Takes every exception the framework has caught since the last call.
///
/// [WidgetTester.takeException] returns only the first one; later ones are
/// only printed.  One is enough to say that the pump was not clean.
List<String> takeExceptions(WidgetTester tester) {
  final result = <String>[];
  while (true) {
    final Object? exception = tester.takeException();
    if (exception == null) break;
    result.add(describeException(exception));
  }
  return result;
}

/// Collects the errors the framework reports while a screen is reached and
/// audited, instead of letting them fail the test.
///
/// `flutter_test` keeps only one pending exception: a second one reported
/// before the first is taken fails the test on the spot.  An overflow or an
/// assertion while a real screen is pumped is evidence about that screen, so
/// every one is recorded on the screen's entry in the log.
class ExceptionRecorder {
  final List<String> _recorded = [];
  FlutterExceptionHandler? _previous;

  void install() {
    _previous = FlutterError.onError;
    FlutterError.onError =
        (details) => _recorded.add(describeException(details.exception));
  }

  /// Must be called before the test ends: the test binding checks that its
  /// own handler is back in place.
  void uninstall() {
    if (_previous != null) FlutterError.onError = _previous;
    _previous = null;
  }

  /// What was recorded since the last call, without repeats.
  List<String> take() {
    final result = _recorded.toSet().toList();
    _recorded.clear();
    return result;
  }
}

/// The first line of an exception, without memory addresses or hash codes.
String describeException(Object exception) {
  final text = exception is FlutterError
      ? exception.toStringShort() == 'FlutterError'
          ? exception.message
          : exception.toString()
      : exception.toString();
  final firstLine = text
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => text);
  return '${exception.runtimeType}: '
      '${firstLine.replaceAll(RegExp(r'#[0-9a-f]{5}\b'), '#…')}';
}

/// Per-isolate log of the screens this run audited, merged into
/// [kScreensLogPath] by [flush].
abstract final class ScreenLog {
  static final Map<String, Map<String, Object>> _screens = {};

  static void audited(
    String screenId,
    A11yAuditResult result, {
    required Size viewSize,
    required double remainingScroll,
    required List<String> exceptions,
    List<String> unhandledRequests = const [],
    List<String> notes = const [],
    List<String> testFontText = const [],
  }) {
    final perRule = <String, int>{};
    var inLib = 0;
    for (final finding in result.findings) {
      perRule[finding.ruleID] = (perRule[finding.ruleID] ?? 0) + 1;
      if (finding.filePath.startsWith('lib/') ||
          finding.filePath.contains('/lib/')) {
        inLib++;
      }
    }
    _screens[screenId] = <String, Object>{
      'status': 'audited',
      'viewSize': '${viewSize.width.round()}x${viewSize.height.round()}',
      'remainingScrollPx': remainingScroll.round(),
      'findingCount': result.findings.length,
      'findingsInLib': inLib,
      'rules': Map.fromEntries(
          perRule.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      if (result.diagnostics.isNotEmpty)
        'diagnostics': [for (final d in result.diagnostics) d.id]..sort(),
      if (exceptions.isNotEmpty) 'exceptions': exceptions,
      if (unhandledRequests.isNotEmpty) 'unhandledRequests': unhandledRequests,
      if (notes.isNotEmpty) 'notes': notes,
      if (testFontText.isNotEmpty) 'textInTestFont': testFontText,
    };
  }

  /// Merges this isolate's screens into [kScreensLogPath].
  static Future<void> flush() async {
    if (_screens.isEmpty) return;
    final file = File(kScreensLogPath);
    file.parent.createSync(recursive: true);
    final merged = <String, Object?>{};
    if (file.existsSync()) {
      try {
        merged.addAll(
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>);
      } on Object {
        // An unreadable log is replaced.
      }
    }
    merged.addAll(_screens);
    final sorted = Map.fromEntries(
        merged.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(sorted)}\n');
  }
}

/// Writes a PNG of the screen to `$A11Y_SCREENSHOT_DIR/<screenId>.png`, when
/// that variable is set.  For checking by eye that a screen was reached and
/// looks as it does in the app; not part of the audit.
Future<void> maybeScreenshot(WidgetTester tester, String screenId) async {
  final dir = Platform.environment['A11Y_SCREENSHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  final renderView = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = renderView.layer! as OffsetLayer;
  final size = tester.view.physicalSize;
  await tester.runAsync(() async {
    // Phone screenshots are saved at 2 px per logical px, wide ones at 1.
    final image = await layer.toImage(Offset.zero & size,
        pixelRatio: tester.view.devicePixelRatio == 1 ? 1 : 2 / 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$dir/${screenId.replaceAll('/', '__')}.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Audits the screen as it stands and records the result.
///
/// [grow] lays a lazy list out in full first; see [growViewToFit].
/// Exceptions thrown while the screen was pumped, or during the audit's own
/// re-layouts, are recorded on the screen rather than failing the test:
/// an overflow or a missing plugin is evidence about the screen.
Future<A11yAuditResult> audit(
  WidgetTester tester,
  String screenId, {
  bool grow = false,
  List<String> exceptionsSoFar = const [],
  ExceptionRecorder? recorder,
  List<String> Function()? unhandledRequests,
  List<String> notes = const [],
}) async {
  final exceptions = [
    ...exceptionsSoFar,
    ...?recorder?.take(),
    ...takeExceptions(tester),
  ];
  var viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  if (grow) {
    viewSize = await growViewToFit(tester);
    exceptions.addAll([...?recorder?.take(), ...takeExceptions(tester)]);
  }
  final remaining = remainingScrollPx(tester);
  final testFontText = textInTestFont(tester);
  await maybeScreenshot(tester, screenId);

  A11yAuditResult result;
  try {
    result =
        await auditScreen(tester, screenId: screenId, config: auditConfig);
  } on A11yReflowException catch (e) {
    // A reflow pass (200 % text or 320 px) was aborted because the app raised
    // an error that is not an overflow while it was re-laid out. That pass
    // contributes no finding; every other phase and pass did complete, and
    // `e.result` (already written to the findings sink) holds their findings.
    // The aborted passes are logged with the screen's other exceptions.
    result = e.result;
    exceptions.addAll([
      for (final failure in e.failures)
        'reflow pass aborted (${failure.pass}): '
            '${describeException(failure.error)}',
    ]);
  }
  exceptions.addAll([...?recorder?.take(), ...takeExceptions(tester)]);

  ScreenLog.audited(screenId, result,
      viewSize: viewSize,
      remainingScroll: remaining,
      exceptions: exceptions,
      unhandledRequests: unhandledRequests?.call() ?? const [],
      notes: notes,
      testFontText: testFontText);
  // ignore: avoid_print
  print('a11y $screenId: ${result.findings.length} finding(s)'
      '${exceptions.isEmpty ? '' : ', ${exceptions.length} exception(s)'}');
  return result;
}
