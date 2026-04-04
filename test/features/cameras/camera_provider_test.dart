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
    if (v is AsyncData<CameraState>) return v.value!;
    if (v is AsyncError) throw v.error!;
    await Future.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('CameraNotifier did not settle');
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
      final state = await waitForCameras(c);
      expect(state.cameras, hasLength(3));
      expect(state.cameras[0].name, 'Nursery');
    });

    test('toggleCamera adds camera', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');

      c.read(cameraNotifierProvider.notifier).toggleCamera('c1');
      expect(c.read(cameraNotifierProvider).value!.selectedIds, {'c1'});
    });

    test('toggleCamera removes already selected', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');

      final n = c.read(cameraNotifierProvider.notifier);
      n.toggleCamera('c1');
      n.toggleCamera('c1');
      expect(c.read(cameraNotifierProvider).value!.selectedIds, isEmpty);
    });

    test('toggleCamera enforces max 2', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');

      final n = c.read(cameraNotifierProvider.notifier);
      n.toggleCamera('c1');
      n.toggleCamera('c2');
      n.toggleCamera('c3'); // should be no-op
      final ids = c.read(cameraNotifierProvider).value!.selectedIds;
      expect(ids, hasLength(2));
      expect(ids, containsAll(['c1', 'c2']));
    });

    test('canStartMonitoring true with 1-2 selected', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');

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

      final state = await waitForCameras(c);
      expect(state.selectedIds, containsAll(['c1', 'c2']));
    });

    test('ignores saved IDs that no longer exist', () async {
      await storage.saveSelectedCameraIds(['c1', 'deleted']);
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');

      final state = await waitForCameras(c);
      expect(state.selectedIds, {'c1'});
    });

    test('persists selection to storage', () async {
      final c = createContainer(storage: storage, api: api);
      addTearDown(c.dispose);
      await waitForCameras(c);
      await c.read(cameraNotifierProvider.notifier).loadCameras('h');

      c.read(cameraNotifierProvider.notifier).toggleCamera('c1');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(await storage.loadSelectedCameraIds(), ['c1']);
    });
  });
}
