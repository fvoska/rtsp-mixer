import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../auth/providers/auth_provider.dart';
import 'camera_state.dart';

class CameraNotifier extends AsyncNotifier<CameraState> {
  @override
  Future<CameraState> build() async => const CameraState();

  Future<void> loadCameras(String host) async {
    state = const AsyncLoading();
    try {
      final client = ref.read(apiClientProvider);
      final cameras = await client.getCameras(host);
      appLog('CAM', 'Loaded ${cameras.length} cameras');

      // Fetch all available RTSPS stream URLs for each camera in parallel.
      final enrichedCameras = await Future.wait(
        cameras.map((c) async {
          final urls = await client.getRtspsUrls(host, c.id);
          return urls.isNotEmpty ? c.copyWith(rtspsStreamUrls: urls) : c;
        }),
      );
      appLog('CAM', 'RTSPS URLs: ${enrichedCameras.where((c) => c.rtspsStreamUrls.isNotEmpty).length}/${cameras.length}');

      final storage = ref.read(storageProvider);
      final savedIds = await storage.loadSelectedCameraIds();
      final validIds = savedIds.where((id) => enrichedCameras.any((c) => c.id == id)).toSet();

      state = AsyncData(CameraState(cameras: enrichedCameras, selectedIds: validIds));
    } catch (e) {
      appLog('CAM', 'Error loading cameras: $e');
      state = AsyncError(e, StackTrace.current);
    }
  }

  void toggleCamera(String cameraId) {
    final current = state.value;
    if (current == null) return;
    final newIds = Set<String>.from(current.selectedIds);
    if (newIds.contains(cameraId)) {
      newIds.remove(cameraId);
      appLog('CAM', 'Deselected camera $cameraId (${newIds.length} selected)');
    } else if (newIds.length < 2) {
      newIds.add(cameraId);
      appLog('CAM', 'Selected camera $cameraId (${newIds.length} selected)');
    } else {
      return;
    }
    state = AsyncData(current.copyWith(selectedIds: newIds));
    ref.read(storageProvider).saveSelectedCameraIds(newIds.toList());
  }
}

final cameraNotifierProvider =
    AsyncNotifierProvider<CameraNotifier, CameraState>(CameraNotifier.new);
