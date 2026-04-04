import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/protect_camera.dart';
import 'camera_state.dart';

class CameraNotifier extends AsyncNotifier<CameraState> {
  bool _loading = false;

  @override
  Future<CameraState> build() async => const CameraState();

  /// Load cameras from cache (fast) then refresh from API (background).
  /// Returns after cache is loaded so callers don't wait for the network.
  Future<void> loadCameras(String host) async {
    if (_loading) {
      appLog('CAM', 'loadCameras already in progress, skipping');
      return;
    }
    _loading = true;

    try {
      final storage = ref.read(storageProvider);
      final savedIds = await storage.loadSelectedCameraIds();

      // Phase 1: Load from cache — instant UI
      final cached = await _loadCachedCameras(storage);
      if (cached != null && cached.isNotEmpty) {
        final validIds = savedIds.where((id) => cached.any((c) => c.id == id)).toSet();
        state = AsyncData(CameraState(cameras: cached, selectedIds: validIds));
        final withUrls = cached.where((c) => c.rtspsStreamUrls.isNotEmpty).length;
        appLog('CAM', 'Loaded ${cached.length} cameras from cache ($withUrls with RTSPS URLs)');
      } else {
        state = const AsyncLoading();
      }

      // Phase 2: Refresh from API — updates state when done
      _refreshFromApi(host, savedIds);
    } catch (e) {
      _loading = false;
      appLog('CAM', 'Error in loadCameras: $e');
      if (!state.hasValue || state.value!.cameras.isEmpty) {
        state = AsyncError(e, StackTrace.current);
      }
    }
  }

  Future<void> _refreshFromApi(String host, List<String> savedIds) async {
    try {
      final client = ref.read(apiClientProvider);
      final storage = ref.read(storageProvider);
      final cameras = await client.getCameras(host);
      appLog('CAM', 'Fetched ${cameras.length} cameras from API');

      // Fetch RTSPS URLs sequentially to avoid 429 rate limiting
      final enrichedCameras = <ProtectCamera>[];
      for (final c in cameras) {
        final urls = await client.getRtspsUrls(host, c.id);
        enrichedCameras.add(urls.isNotEmpty ? c.copyWith(rtspsStreamUrls: urls) : c);
      }
      appLog('CAM', 'RTSPS URLs: ${enrichedCameras.where((c) => c.rtspsStreamUrls.isNotEmpty).length}/${cameras.length}');

      await _saveCachedCameras(storage, enrichedCameras);

      final validIds = savedIds.where((id) => enrichedCameras.any((c) => c.id == id)).toSet();
      state = AsyncData(CameraState(cameras: enrichedCameras, selectedIds: validIds));
    } catch (e) {
      appLog('CAM', 'Error refreshing cameras from API: $e');
      if (state.hasValue && state.value!.cameras.isNotEmpty) {
        appLog('CAM', 'Keeping cached camera list');
      }
    } finally {
      _loading = false;
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
