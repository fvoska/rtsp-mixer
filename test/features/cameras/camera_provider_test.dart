import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rtsp_audio_mixer/core/api/protect_api_client.dart';
import 'package:rtsp_audio_mixer/core/api/protect_api_client_provider.dart';
import 'package:rtsp_audio_mixer/core/api/protect_auth_interceptor.dart';
import 'package:rtsp_audio_mixer/core/models/app_error.dart';
import 'package:rtsp_audio_mixer/core/storage/secure_storage_provider.dart';
import 'package:rtsp_audio_mixer/core/storage/secure_storage_service.dart';
import 'package:rtsp_audio_mixer/features/cameras/models/protect_camera.dart';
import 'package:rtsp_audio_mixer/features/cameras/models/stream_channel.dart';
import 'package:rtsp_audio_mixer/features/cameras/providers/camera_provider.dart';
import 'package:rtsp_audio_mixer/features/cameras/providers/camera_state.dart';

import '../../core/storage/fake_flutter_secure_storage.dart';

/// Fake API client for testing camera flows.
class FakeProtectApiClient extends ProtectApiClient {
  List<ProtectCamera> bootstrapResult = [];
  AppError? bootstrapError;

  FakeProtectApiClient()
      : super(
          dio: Dio(),
          authInterceptor: ProtectAuthInterceptor(),
        );

  @override
  Future<bool> login(String host, String username, String password) async {
    return true;
  }

  @override
  Future<List<ProtectCamera>> getBootstrap(String host) async {
    if (bootstrapError != null) throw bootstrapError!;
    return bootstrapResult;
  }
}

const _testCameras = [
  ProtectCamera(
    id: 'cam-001',
    name: 'Nursery',
    type: 'UVC G4 Dome',
    state: 'CONNECTED',
    isConnected: true,
    channels: [
      StreamChannel(id: 0, name: 'High', rtspAlias: 'nursery_high', isRtspEnabled: true),
    ],
  ),
  ProtectCamera(
    id: 'cam-002',
    name: 'Bedroom',
    type: 'UVC G4 Instant',
    state: 'CONNECTED',
    isConnected: true,
    channels: [
      StreamChannel(id: 0, name: 'High', rtspAlias: 'bedroom_high', isRtspEnabled: true),
    ],
  ),
  ProtectCamera(
    id: 'cam-003',
    name: 'Garage',
    type: 'UVC G3 Flex',
    state: 'DISCONNECTED',
    isConnected: false,
    channels: [
      StreamChannel(id: 0, name: 'High', rtspAlias: 'garage_high', isRtspEnabled: true),
    ],
  ),
];

ProviderContainer createContainer({
  required SecureStorageService storage,
  required ProtectApiClient apiClient,
}) {
  return ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      protectApiClientProvider.overrideWithValue(apiClient),
    ],
  );
}

Future<CameraState> waitForCameraState(ProviderContainer container) async {
  CameraState? result;
  for (var i = 0; i < 100; i++) {
    final value = container.read(cameraNotifierProvider);
    if (value is AsyncData<CameraState>) {
      result = value.value;
      break;
    }
    if (value is AsyncError) {
      throw value.error!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (result == null) {
    throw StateError('CameraNotifier did not settle within timeout');
  }
  return result;
}

void main() {
  late FakeFlutterSecureStorage fakeStorage;
  late SecureStorageService storageService;
  late FakeProtectApiClient fakeApiClient;

  setUp(() {
    fakeStorage = FakeFlutterSecureStorage();
    storageService = SecureStorageService(fakeStorage);
    fakeApiClient = FakeProtectApiClient();
    fakeApiClient.bootstrapResult = List.of(_testCameras);
  });

  group('CameraNotifier', () {
    test('loadCameras populates camera list', () async {
      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      // Wait for initial empty build
      await waitForCameraState(container);

      // Load cameras
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      final state = await waitForCameraState(container);
      expect(state.cameras.length, 3);
      expect(state.cameras[0].name, 'Nursery');
      expect(state.selectedIds, isEmpty);
    });

    test('toggleCamera adds camera to selection', () async {
      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForCameraState(container);
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      notifier.toggleCamera('cam-001');

      final state = container.read(cameraNotifierProvider).value!;
      expect(state.selectedIds, contains('cam-001'));
      expect(state.selectedIds.length, 1);
    });

    test('toggleCamera removes already selected camera', () async {
      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForCameraState(container);
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      notifier.toggleCamera('cam-001');
      notifier.toggleCamera('cam-001');

      final state = container.read(cameraNotifierProvider).value!;
      expect(state.selectedIds, isEmpty);
    });

    test('toggleCamera does nothing when 2 already selected and adding third', () async {
      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForCameraState(container);
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      notifier.toggleCamera('cam-001');
      notifier.toggleCamera('cam-002');
      notifier.toggleCamera('cam-003'); // should be no-op

      final state = container.read(cameraNotifierProvider).value!;
      expect(state.selectedIds.length, 2);
      expect(state.selectedIds, containsAll(['cam-001', 'cam-002']));
      expect(state.selectedIds.contains('cam-003'), isFalse);
    });

    test('canStartMonitoring true with 1 camera selected', () async {
      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForCameraState(container);
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      notifier.toggleCamera('cam-001');

      final state = container.read(cameraNotifierProvider).value!;
      expect(state.canStartMonitoring, isTrue);
    });

    test('canStartMonitoring true with 2 cameras selected', () async {
      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForCameraState(container);
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      notifier.toggleCamera('cam-001');
      notifier.toggleCamera('cam-002');

      final state = container.read(cameraNotifierProvider).value!;
      expect(state.canStartMonitoring, isTrue);
    });

    test('canStartMonitoring false with 0 cameras selected', () async {
      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForCameraState(container);
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      final state = container.read(cameraNotifierProvider).value!;
      expect(state.canStartMonitoring, isFalse);
    });

    test('selectedCameras returns correct camera objects', () async {
      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForCameraState(container);
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      notifier.toggleCamera('cam-001');
      notifier.toggleCamera('cam-003');

      final state = container.read(cameraNotifierProvider).value!;
      expect(state.selectedCameras.length, 2);
      expect(state.selectedCameras.map((c) => c.name), containsAll(['Nursery', 'Garage']));
    });

    test('pre-selects saved camera IDs on loadCameras (D-08)', () async {
      // Pre-save selected camera IDs
      await storageService.saveSelectedCameraIds(['cam-001', 'cam-002']);

      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForCameraState(container);
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      final state = await waitForCameraState(container);
      expect(state.selectedIds, containsAll(['cam-001', 'cam-002']));
    });

    test('ignores saved IDs that no longer exist in camera list', () async {
      await storageService.saveSelectedCameraIds(['cam-001', 'cam-deleted']);

      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForCameraState(container);
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      final state = await waitForCameraState(container);
      expect(state.selectedIds, contains('cam-001'));
      expect(state.selectedIds.contains('cam-deleted'), isFalse);
    });

    test('persists selected camera IDs to secure storage on toggle', () async {
      final container = createContainer(
        storage: storageService,
        apiClient: fakeApiClient,
      );
      addTearDown(container.dispose);

      await waitForCameraState(container);
      final notifier = container.read(cameraNotifierProvider.notifier);
      await notifier.loadCameras('192.168.1.1');

      notifier.toggleCamera('cam-001');
      // Give async persist time to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final savedIds = await storageService.loadSelectedCameraIds();
      expect(savedIds, contains('cam-001'));
    });
  });
}
