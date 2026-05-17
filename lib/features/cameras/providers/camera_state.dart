import '../models/protect_camera.dart';

class CameraState {
  final List<ProtectCamera> cameras;
  final Set<String> selectedIds;

  const CameraState({this.cameras = const [], this.selectedIds = const {}});

  bool get canStartMonitoring => selectedIds.isNotEmpty;

  bool get hasPerformanceRisk => selectedIds.length > 2;

  List<ProtectCamera> get selectedCameras =>
      cameras.where((c) => selectedIds.contains(c.id)).toList();

  CameraState copyWith({List<ProtectCamera>? cameras, Set<String>? selectedIds}) =>
      CameraState(
        cameras: cameras ?? this.cameras,
        selectedIds: selectedIds ?? this.selectedIds,
      );
}
