import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/main.dart';
import 'package:vid_downloader_app/media_library.dart';

class _TestMediaLibrary implements MediaLibrary {
  const _TestMediaLibrary();

  @override
  Future<PermissionState> requestPermission() async =>
      PermissionState.authorized;

  @override
  Future<List<AssetEntity>> loadPage({
    required RequestType type,
    required int page,
    required int pageSize,
  }) async {
    return const [];
  }

  @override
  void invalidateCache() {}
}

class _EmptyBackendSettingsStore implements BackendSettingsStore {
  BackendSettings settings = BackendSettings.fromInput(
    baseUrl: 'http://10.0.2.2:8787',
    apiKey: '',
  );

  @override
  Future<BackendSettings> load() async => settings;

  @override
  Future<void> save(BackendSettings value) async {
    settings = value;
  }
}

void main() {
  testWidgets('download page preview', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: VidSaveHomePage(
          library: _TestMediaLibrary(),
          backendSettingsStore: _EmptyBackendSettingsStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(VidSaveHomePage),
      matchesGoldenFile('golden/download_page.png'),
    );
  });
}
