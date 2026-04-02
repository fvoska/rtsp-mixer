import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/protect_api_client_provider.dart';
import '../../../core/storage/secure_storage_provider.dart';
import 'camera_state.dart';

/// Camera list and selection notifier.
///
/// Loads cameras from bootstrap API (D-04, D-05), pre-selects previously
/// saved cameras (D-08), and enforces 1-2 selection limit (D-06).
class CameraNotifier extends AsyncNotifier<CameraState> {
  @override
  Future<CameraState> build() async {
    return const CameraState();
  }

  /// Load cameras from the Protect bootstrap API and pre-select saved cameras.
  Future<void> loadCameras(String host) async {
    state = const AsyncLoading();

    try {
      final client = ref.read(protectApiClientProvider);
      final cameras = await client.getBootstrap(host);

      final storage = ref.read(secureStorageProvider);
      final savedIds = await storage.loadSelectedCameraIds();

      // Pre-select cameras that match saved IDs and still exist (D-08)
      final validIds = savedIds
          .where((id) => cameras.any((c) => c.id == id))
          .toSet();

      state = AsyncData(CameraState(
        cameras: cameras,
        selectedIds: validIds,
      ));
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }

  /// Toggle camera selection. Enforces max 2 selection limit (D-06).
  ///
  /// - If camera is selected: removes it
  /// - If camera is not selected and < 2 selected: adds it
  /// - If camera is not selected and 2 already selected: no-op
  void toggleCamera(String cameraId) {
    final current = state.value;
    if (current == null) return;

    final newIds = Set<String>.from(current.selectedIds);

    if (newIds.contains(cameraId)) {
      newIds.remove(cameraId);
    } else if (newIds.length < 2) {
      newIds.add(cameraId);
    } else {
      // Already 2 selected, do nothing (per UI-SPEC)
      return;
    }

    state = AsyncData(current.copyWith(selectedIds: newIds));

    // Persist selection asynchronously
    _persistSelection(newIds.toList());
  }

  Future<void> _persistSelection(List<String> ids) async {
    final storage = ref.read(secureStorageProvider);
    await storage.saveSelectedCameraIds(ids);
  }
}

/// Provider for the camera notifier.
final cameraNotifierProvider =
    AsyncNotifierProvider<CameraNotifier, CameraState>(CameraNotifier.new);
