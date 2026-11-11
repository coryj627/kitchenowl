/// Stand-ins for what the app expects from the device it runs on: plugins,
/// the cache directory, the preferences store and the image cache.
///
/// Nothing here is a screen or a widget.  See `../README.md`, "What had to be
/// faked".
library;

import 'dart:io' as io;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart';
import 'package:file/file.dart' as f;
import 'package:file/memory.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenowl/services/storage/storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// The directory the fake `path_provider` hands out.  Files under it live in
/// memory ([_memoryFiles]); every other path is the real file system.
const String kFakeDeviceRoot = '/a11y-fake-device';

/// The app's cache and support directories, in memory.
///
/// The app reads and writes its offline copy of the user, households, lists
/// and recipes with `dart:io` files.  Real file I/O never completes inside a
/// widget test's fake clock, so files under [kFakeDeviceRoot] are served from
/// memory, where every future completes on a microtask.
MemoryFileSystem _memoryFiles = MemoryFileSystem();

final class _DeviceFiles extends io.IOOverrides {
  @override
  io.File createFile(String path) => path.startsWith(kFakeDeviceRoot)
      ? _memoryFiles.file(path)
      : super.createFile(path);

  @override
  io.Directory createDirectory(String path) => path.startsWith(kFakeDeviceRoot)
      ? _memoryFiles.directory(path)
      : super.createDirectory(path);
}

class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationCachePath() async => '$kFakeDeviceRoot/cache';

  @override
  Future<String?> getApplicationSupportPath() async =>
      '$kFakeDeviceRoot/support';

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      '$kFakeDeviceRoot/documents';

  @override
  Future<String?> getTemporaryPath() async => '$kFakeDeviceRoot/tmp';
}

/// `device_info_plus` picks the model class from the HOST operating system
/// (`Platform.isMacOS`, `Platform.isLinux`), so the fake answers with what
/// the host's branch expects.  The app only reads a device name from it, to
/// label the session when signing in.
class _FakeDeviceInfo extends DeviceInfoPlatform {
  @override
  Future<BaseDeviceInfo> deviceInfo() async {
    if (io.Platform.isLinux) {
      return LinuxDeviceInfo(
        name: 'Linux',
        id: 'linux',
        prettyName: 'Test device',
        machineId: null,
      );
    }
    return BaseDeviceInfo(<String, dynamic>{
      // macOS
      'computerName': 'Test device',
      'hostName': 'test-device',
      'arch': 'arm64',
      'model': 'Test1,1',
      'modelName': 'Test device',
      'kernelVersion': 'Test',
      'osRelease': '1.0',
      'majorVersion': 1,
      'minorVersion': 0,
      'patchVersion': 0,
      'activeCPUs': 8,
      'memorySize': 17179869184,
      'cpuFrequency': 0,
      'systemGUID': null,
      // Windows
      'numberOfCores': 8,
      'systemMemoryInMegabytes': 16384,
    });
  }
}

/// Keep-screen-on, remembered and otherwise ignored.
class _FakeWakelock extends WakelockPlusPlatformInterface {
  bool _enabled = false;

  @override
  Future<void> toggle({required bool enable}) async => _enabled = enable;

  @override
  Future<bool> get enabled async => _enabled;
}

/// The app's image cache, answered from memory.
///
/// Every image in the app goes through `CachedNetworkImageProvider`, whose
/// default cache manager needs sqflite, a temporary directory and real file
/// I/O.  `CachedNetworkImageProvider.defaultCacheManager` is a settable
/// static, so the harness swaps in this manager, which answers any URL with
/// [imageFor]'s bytes.  The bytes are still decoded by the engine.
class FakeImageCache implements BaseCacheManager, ImageCacheManager {
  FakeImageCache(this.imageFor);

  /// PNG bytes for a URL, or null for "the server has no such image".
  final Uint8List? Function(String url) imageFor;

  final MemoryFileSystem _files = MemoryFileSystem();
  int _next = 0;

  /// The URLs asked for since the last [takeRequested].
  final List<String> requested = [];

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    requested.add(url);
    final bytes = imageFor(url);
    if (bytes == null) {
      throw HttpExceptionWithStatus(404, 'No image at $url',
          uri: Uri.parse(url));
    }
    final f.File file = _files.file('/image-${_next++}.png')
      ..writeAsBytesSync(bytes);
    yield FileInfo(
      file,
      FileSource.Cache,
      DateTime.utc(2100),
      url,
    );
  }

  /// The app asks for some images at a maximum size.  The same picture is
  /// served; the framework scales it when it paints.
  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) =>
      getFileStream(url, key: key, headers: headers);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'a11y harness: FakeImageCache.${invocation.memberName}');
}

/// Installs every fake in this file.  Call once per test, before the app is
/// built; [resetFakeDevice] undoes what a test left behind.
///
/// [preferences] seeds the app's settings (`SharedPreferences`), [token] the
/// saved sign-in token (secure storage).
Future<void> installFakeDevice({
  required FakeImageCache images,
  Map<String, Object> preferences = const {},
  String? token,
}) async {
  io.IOOverrides.global = _DeviceFiles();
  _memoryFiles = MemoryFileSystem();
  for (final directory in ['cache', 'support', 'documents', 'tmp']) {
    _memoryFiles
        .directory('$kFakeDeviceRoot/$directory')
        .createSync(recursive: true);
  }
  PathProviderPlatform.instance = _FakePathProvider();
  DeviceInfoPlatform.instance = _FakeDeviceInfo();
  CachedNetworkImageProvider.defaultCacheManager = images;
  wakelockPlusPlatformInstance = _FakeWakelock();

  // The build number is compared with the server's minimum frontend version.
  PackageInfo.setMockInitialValues(
    appName: 'KitchenOwl',
    packageName: 'com.tombursch.kitchenowl',
    version: '0.8.1',
    buildNumber: '126',
    buildSignature: '',
  );

  FlutterSecureStorage.setMockInitialValues(
      {if (token != null) 'TOKEN': token});

  final prefs = _preferences ??
      (throw StateError('a11y harness: call installPreferencesStore first'));
  await prefs.clear();
  for (final MapEntry(:key, :value) in preferences.entries) {
    switch (value) {
      case final bool v:
        await prefs.setBool(key, v);
      case final int v:
        await prefs.setInt(key, v);
      case final String v:
        await prefs.setString(key, v);
      default:
        throw ArgumentError('a11y harness: preference $key: $value');
    }
  }

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  // No Material You palette, as on a device without dynamic colour.
  messenger.setMockMethodCallHandler(
    const MethodChannel('io.material.plugins/dynamic_color'),
    (call) async => null,
  );
  // "Open in browser" is answered and otherwise ignored.
  for (final channel in _ignoredChannels) {
    messenger.setMockMethodCallHandler(
        MethodChannel(channel), (call) async => null);
  }
}

SharedPreferences? _preferences;

/// Creates the one preferences store of this test isolate.  Call it from
/// `setUpAll`, OUTSIDE any test.
///
/// The app's `PreferenceStorage` singleton keeps a `Future<SharedPreferences>`
/// for the life of the isolate.  A future created inside one widget test
/// belongs to that test's fake-async zone, and a later test that awaits it
/// waits for a microtask queue nobody flushes any more: the app would hang on
/// its splash page from the second test on.  Created here, the future belongs
/// to the root zone, and its listeners run whenever real time passes (the
/// harness's `settle` lets it, between pumps).
Future<void> installPreferencesStore() async {
  SharedPreferences.setMockInitialValues({});
  _preferences = await SharedPreferences.getInstance();
  PreferenceStorage.getInstance();
}

const List<String> _ignoredChannels = [
  'plugins.flutter.io/url_launcher',
  'plugins.flutter.io/url_launcher_macos',
  'plugins.flutter.io/url_launcher_linux',
];

/// Removes the global overrides installed by [installFakeDevice].
void resetFakeDevice() {
  io.IOOverrides.global = null;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('io.material.plugins/dynamic_color'),
    null,
  );
  for (final channel in _ignoredChannels) {
    messenger.setMockMethodCallHandler(MethodChannel(channel), null);
  }
}
