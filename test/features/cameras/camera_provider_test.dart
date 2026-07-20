import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/api/protect_api_client.dart';
import 'package:rtsp_mixer/core/storage/storage_service.dart';
import 'package:rtsp_mixer/features/auth/providers/auth_provider.dart';
import 'package:rtsp_mixer/features/cameras/models/protect_camera.dart';
import 'package:rtsp_mixer/features/cameras/providers/camera_provider.dart';
import 'package:rtsp_mixer/features/cameras/providers/camera_state.dart';

class FakeApiClient extends ProtectApiClient {
  List<ProtectCamera> cameras = const [
    ProtectCamera(id: 'c1', name: 'Nursery', state: 'CONNECTED'),
    ProtectCamera(id: 'c2', name: 'Bedroom', state: 'CONNECTED'),
    ProtectCamera(id: 'c3', name: 'Garage', state: 'DISCONNECTED'),
  ];

  @override
  Future<bool> verifyConnection(String host) async => true;

  @override
  Future<List<ProtectCamera>> getCameras(String host) async => cameras;

  @override
  Future<Map<String, String>> getRtspsUrls(String host, String cameraId) async =>
      {'low': 'rtsps://fake:7441/$cameraId'};
}

ProviderContainer createContainer({
  required StorageService storage,
  required ProtectApiClient api,
}) {
  return ProviderContainer(overrides: [
    storageProvider.overrideWithValue(storage),
    apiClientProvider.overrideWithValue(api),
  ]);
}

Future<CameraState> waitForCameras(ProviderContainer c) async {
  for (var i = 0; i < 100; i++) {
    final v = c.read(cameraNotifierProvider);
    if (v is AsyncData<CameraState>) return v.value;
    if (v is AsyncError) throw v.error!;
    await Future.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('CameraNotifier did not settle');
}

/// Wait for cameras to have RTSPS URLs (background refresh complete).
Future<CameraState> waitForCamerasWithUrls(ProviderContainer c) async {
  for (var i = 0; i < 100; i++) {
    final v = c.read(cameraNotifierProvider);
    if (v is AsyncData<CameraState> &&
        v.value.cameras.isNotEmpty &&
        v.value.cameras.every((cam) => cam.rtspsStreamUrls.isNotEmpty)) {
      return v.value;
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Cameras did not get RTSPS URLs');
}

void main() {
  late StorageService storage;
  late FakeApiClient api;

  setUp(() {
    storage = StorageService();
    api = FakeApiClient();
  });

  group('CameraNotifier', () {
    test('loadCameras populates list', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);

      await c.read(cameraNotifierProvider.notifier).loadCameras('10.0.0.1');
      final state = await waitForCamerasWithUrls(c);
      expect(state.cameras, hasLength(3));
      expect(state.cameras[0].name, 'Nursery');
    });

    test('toggleCamera adds camera', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');
      await waitForCamerasWithUrls(c);

      c.read(cameraNotifierProvider.notifier).toggleCamera('c1');
      expect(c.read(cameraNotifierProvider).value!.selectedIds, {'c1'});
    });

    test('toggleCamera removes already selected', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');
      await waitForCamerasWithUrls(c);

      final n = c.read(cameraNotifierProvider.notifier);
      n.toggleCamera('c1');
      n.toggleCamera('c1');
      expect(c.read(cameraNotifierProvider).value!.selectedIds, isEmpty);
    });

    test('toggleCamera allows more than 2 selections', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');
      await waitForCamerasWithUrls(c);

      final n = c.read(cameraNotifierProvider.notifier);
      n.toggleCamera('c1');
      n.toggleCamera('c2');
      n.toggleCamera('c3');
      final ids = c.read(cameraNotifierProvider).value!.selectedIds;
      expect(ids, hasLength(3));
      expect(ids, containsAll(['c1', 'c2', 'c3']));
    });

    test('canStartMonitoring true with 1-2 selected', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');
      await waitForCamerasWithUrls(c);

      expect(c.read(cameraNotifierProvider).value!.canStartMonitoring, false);
      c.read(cameraNotifierProvider.notifier).toggleCamera('c1');
      expect(c.read(cameraNotifierProvider).value!.canStartMonitoring, true);
      c.read(cameraNotifierProvider.notifier).toggleCamera('c2');
      expect(c.read(cameraNotifierProvider).value!.canStartMonitoring, true);
    });

    test('pre-selects saved camera IDs', () async {
      await storage.saveSelectedCameraIds(['c1', 'c2']);
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');
      await waitForCamerasWithUrls(c);

      final state = c.read(cameraNotifierProvider).value!;
      expect(state.selectedIds, containsAll(['c1', 'c2']));
    });

    test('ignores saved IDs that no longer exist', () async {
      await storage.saveSelectedCameraIds(['c1', 'deleted']);
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');
      await waitForCamerasWithUrls(c);

      final state = c.read(cameraNotifierProvider).value!;
      expect(state.selectedIds, {'c1'});
    });

    test('persists selection to storage', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');
      await waitForCamerasWithUrls(c);

      c.read(cameraNotifierProvider.notifier).toggleCamera('c1');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(await storage.loadSelectedCameraIds(), ['c1']);
    });
  });

  group('CameraNotifier manual cameras', () {
    test('addManualCamera appends a manual camera, selects it, and persists',
        () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');
      await waitForCamerasWithUrls(c);

      final n = c.read(cameraNotifierProvider.notifier);
      await n.addManualCamera(url: 'rtsp://10.0.0.9:554/live', name: 'Attic');

      final state = c.read(cameraNotifierProvider).value!;
      final manual = state.cameras.where((cam) => cam.isManual).toList();
      expect(manual, hasLength(1));
      expect(manual.first.name, 'Attic');
      expect(manual.first.defaultStreamUrl, 'rtsp://10.0.0.9:554/live');
      // Manual camera is appended after the Unifi cameras.
      expect(state.cameras.last.isManual, true);
      // Auto-selected and mixed-source flag flips on.
      expect(state.selectedIds, contains(manual.first.id));
      expect(state.hasMixedSources, true);
      // Persisted.
      expect(await storage.loadManualCameras(), hasLength(1));
    });

    test('removeManualCamera removes it and clears selection', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');
      await waitForCamerasWithUrls(c);

      final n = c.read(cameraNotifierProvider.notifier);
      await n.addManualCamera(url: 'rtsp://10.0.0.9:554/live');
      final added = c
          .read(cameraNotifierProvider)
          .value!
          .cameras
          .firstWhere((cam) => cam.isManual);

      await n.removeManualCamera(added.id);
      final state = c.read(cameraNotifierProvider).value!;
      expect(state.cameras.where((cam) => cam.isManual), isEmpty);
      expect(state.selectedIds, isNot(contains(added.id)));
      expect(await storage.loadManualCameras(), isEmpty);
    });

    test('loadCameras() with no host shows only manual cameras', () async {
      await storage.saveManualCameras([
        ProtectCamera.manual(id: 'manual-1', url: 'rtsp://x/y', name: 'Shed')
            .toJson(),
      ]);
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);

      await c.read(cameraNotifierProvider.notifier).loadCameras();
      final state = c.read(cameraNotifierProvider).value!;
      expect(state.cameras, hasLength(1));
      expect(state.cameras.first.isManual, true);
      expect(state.cameras.first.name, 'Shed');
      // Only one source type — no distinction needed.
      expect(state.hasMixedSources, false);
    });

    test('manual cameras survive a Unifi API refresh', () async {
      await storage.saveManualCameras([
        ProtectCamera.manual(id: 'manual-1', url: 'rtsp://x/y', name: 'Shed')
            .toJson(),
      ]);
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);

      await c.read(cameraNotifierProvider.notifier).loadCameras('h');
      // The list starts with just the manual camera, then the Unifi API
      // refresh appends the 3 fake cameras — wait for the full merged list.
      for (var i = 0; i < 100; i++) {
        final s = c.read(cameraNotifierProvider).value;
        if (s != null && s.cameras.length == 4) break;
        await Future.delayed(const Duration(milliseconds: 10));
      }

      final state = c.read(cameraNotifierProvider).value!;
      // 3 Unifi (fake) + 1 manual.
      expect(state.cameras, hasLength(4));
      expect(state.cameras.where((cam) => cam.isManual), hasLength(1));
      expect(state.hasMixedSources, true);
    });
  });
}
