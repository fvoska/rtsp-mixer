import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/protect_camera.dart';
import 'camera_state.dart';

class CameraNotifier extends AsyncNotifier<CameraState> {
  @override
  Future<CameraState> build() async => const CameraState();

  Future<void> loadCameras(String host) async {
    final storage = ref.read(storageProvider);

    // Load cached cameras immediately for instant UI
    final cached = await _loadCachedCameras(storage);
    final savedIds = await storage.loadSelectedCameraIds();

    if (cached != null && cached.isNotEmpty) {
      final validIds = savedIds.where((id) => cached.any((c) => c.id == id)).toSet();
      state = AsyncData(CameraState(cameras: cached, selectedIds: validIds));
      final withUrls = cached.where((c) => c.rtspsStreamUrls.isNotEmpty).length;
      appLog('CAM', 'Loaded ${cached.length} cameras from cache ($withUrls with RTSPS URLs)');
    } else {
      state = const AsyncLoading();
    }

    // Fetch fresh data in background
    try {
      final client = ref.read(apiClientProvider);
      final cameras = await client.getCameras(host);
      appLog('CAM', 'Fetched ${cameras.length} cameras from API');

      final enrichedCameras = await Future.wait(
        cameras.map((c) async {
          final urls = await client.getRtspsUrls(host, c.id);
          return urls.isNotEmpty ? c.copyWith(rtspsStreamUrls: urls) : c;
        }),
      );
      appLog('CAM', 'RTSPS URLs: ${enrichedCameras.where((c) => c.rtspsStreamUrls.isNotEmpty).length}/${cameras.length}');

      // Save to cache for next startup
      await _saveCachedCameras(storage, enrichedCameras);

      final validIds = savedIds.where((id) => enrichedCameras.any((c) => c.id == id)).toSet();
      state = AsyncData(CameraState(cameras: enrichedCameras, selectedIds: validIds));
    } catch (e) {
      appLog('CAM', 'Error loading cameras: $e');
      // If we have cached data, keep showing it instead of error
      if (state.hasValue && state.value!.cameras.isNotEmpty) {
        appLog('CAM', 'Keeping cached camera list');
      } else {
        state = AsyncError(e, StackTrace.current);
      }
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

  Future<List<ProtectCamera>?> _loadCachedCameras(dynamic storage) async {
    try {
      final raw = await storage.read('cached_cameras');
      if (raw == null) return null;
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((j) => ProtectCamera.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      appLog('CAM', 'Failed to load camera cache: $e');
      return null;
    }
  }

  Future<void> _saveCachedCameras(dynamic storage, List<ProtectCamera> cameras) async {
    try {
      await storage.write('cached_cameras', jsonEncode(cameras.map((c) => c.toJson()).toList()));
    } catch (e) {
      appLog('CAM', 'Failed to save camera cache: $e');
    }
  }
}

final cameraNotifierProvider =
    AsyncNotifierProvider<CameraNotifier, CameraState>(CameraNotifier.new);
