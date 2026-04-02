import '../models/protect_camera.dart';

/// State for the camera list and selection.
class CameraState {
  final List<ProtectCamera> cameras;
  final Set<String> selectedIds;

  const CameraState({
    this.cameras = const [],
    this.selectedIds = const {},
  });

  /// Whether the user can start monitoring (1 or 2 cameras selected).
  bool get canStartMonitoring =>
      selectedIds.isNotEmpty && selectedIds.length <= 2;

  /// The currently selected cameras.
  List<ProtectCamera> get selectedCameras =>
      cameras.where((c) => selectedIds.contains(c.id)).toList();

  CameraState copyWith({
    List<ProtectCamera>? cameras,
    Set<String>? selectedIds,
  }) {
    return CameraState(
      cameras: cameras ?? this.cameras,
      selectedIds: selectedIds ?? this.selectedIds,
    );
  }
}
