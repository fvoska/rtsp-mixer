import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/protect_camera.dart';
import 'camera_state.dart';

class CameraNotifier extends AsyncNotifier<CameraState> {
  bool _loading = false;

  /// Cameras discovered from the Unifi Protect API (empty in manual-only mode).
  List<ProtectCamera> _unifiCameras = [];

  /// Manually-entered RTSP cameras, persisted locally.
  List<ProtectCamera> _manualCameras = [];

  /// Authoritative selection set, kept in sync with storage. Composed state's
  /// selectedIds is always this filtered down to cameras that still exist.
  Set<String> _selectedIds = {};

  @override
  Future<CameraState> build() async => const CameraState();

  /// The full camera list = Unifi cameras first, then manual cameras appended.
  CameraState _compose() {
    final all = [..._unifiCameras, ..._manualCameras];
    final validIds =
        _selectedIds.where((id) => all.any((c) => c.id == id)).toSet();
    return CameraState(cameras: all, selectedIds: validIds);
  }

  void _publish() => state = AsyncData(_compose());

  /// Load cameras. Always loads manual cameras (and the saved selection). When
  /// [host] is non-null (Unifi mode) it also loads the Unifi cache instantly
  /// then refreshes from the API in the background. When [host] is null
  /// (manual-only mode) only manual cameras are shown.
  Future<void> loadCameras([String? host]) async {
    if (_loading) {
      appLog('CAM', 'loadCameras already in progress, skipping');
      return;
    }
    _loading = true;

    try {
      final storage = ref.read(storageProvider);
      _selectedIds = (await storage.loadSelectedCameraIds()).toSet();
      _manualCameras = await _loadManualCameras(storage);
      appLog('CAM', 'Loaded ${_manualCameras.length} manual cameras');

      if (host == null) {
        // Manual-only mode — no Unifi console configured.
        _unifiCameras = [];
        _publish();
        _loading = false;
        return;
      }

      // Phase 1: Load Unifi cameras from cache — instant UI.
      final cached = await _loadCachedCameras(storage);
      if (cached != null && cached.isNotEmpty) {
        _unifiCameras = cached;
        _publish();
        final withUrls = cached.where((c) => c.rtspsStreamUrls.isNotEmpty).length;
        appLog('CAM', 'Loaded ${cached.length} Unifi cameras from cache ($withUrls with RTSPS URLs)');
      } else if (_manualCameras.isNotEmpty) {
        // No Unifi cache yet but we have manual cameras — show them immediately
        // instead of a blank loading spinner.
        _unifiCameras = [];
        _publish();
      } else {
        state = const AsyncLoading();
      }

      // Phase 2: Refresh Unifi cameras from API — updates state when done.
      _refreshFromApi(host);
    } catch (e) {
      _loading = false;
      appLog('CAM', 'Error in loadCameras: $e');
      if (!state.hasValue || state.value!.cameras.isEmpty) {
        state = AsyncError(e, StackTrace.current);
      }
    }
  }

  Future<void> _refreshFromApi(String host) async {
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

      _unifiCameras = enrichedCameras;
      _publish();
    } catch (e) {
      appLog('CAM', 'Error refreshing cameras from API: $e');
      if (_unifiCameras.isNotEmpty || _manualCameras.isNotEmpty) {
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
    } else {
      newIds.add(cameraId);
      appLog('CAM', 'Selected camera $cameraId (${newIds.length} selected)');
    }
    _selectedIds = newIds;
    state = AsyncData(current.copyWith(selectedIds: newIds));
    ref.read(storageProvider).saveSelectedCameraIds(newIds.toList());
  }

  /// Add a manually-entered RTSP camera and persist it. The newly-added camera
  /// is auto-selected so the user can start monitoring it right away.
  Future<void> addManualCamera({required String url, String? name}) async {
    final trimmedUrl = url.trim();
    final trimmedName = name?.trim();
    final id = 'manual-${DateTime.now().microsecondsSinceEpoch}';
    final camera = ProtectCamera.manual(
      id: id,
      url: trimmedUrl,
      name: (trimmedName == null || trimmedName.isEmpty) ? null : trimmedName,
    );
    _manualCameras = [..._manualCameras, camera];
    _selectedIds = {..._selectedIds, id};
    appLog('CAM', 'Added manual camera "${camera.name ?? id}" ($trimmedUrl)');
    await _saveManualCameras();
    await ref.read(storageProvider).saveSelectedCameraIds(_selectedIds.toList());
    _publish();
  }

  /// Remove a manually-entered camera. No-op for Unifi cameras.
  Future<void> removeManualCamera(String cameraId) async {
    if (!_manualCameras.any((c) => c.id == cameraId)) return;
    _manualCameras = _manualCameras.where((c) => c.id != cameraId).toList();
    _selectedIds = {..._selectedIds}..remove(cameraId);
    appLog('CAM', 'Removed manual camera $cameraId');
    await _saveManualCameras();
    await ref.read(storageProvider).saveSelectedCameraIds(_selectedIds.toList());
    _publish();
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

  Future<List<ProtectCamera>> _loadManualCameras(dynamic storage) async {
    try {
      final list = await storage.loadManualCameras() as List<Map<String, dynamic>>;
      return list.map(ProtectCamera.fromJson).toList();
    } catch (e) {
      appLog('CAM', 'Failed to load manual cameras: $e');
      return [];
    }
  }

  Future<void> _saveManualCameras() async {
    try {
      await ref
          .read(storageProvider)
          .saveManualCameras(_manualCameras.map((c) => c.toJson()).toList());
    } catch (e) {
      appLog('CAM', 'Failed to save manual cameras: $e');
    }
  }
}

final cameraNotifierProvider =
    AsyncNotifierProvider<CameraNotifier, CameraState>(CameraNotifier.new);
