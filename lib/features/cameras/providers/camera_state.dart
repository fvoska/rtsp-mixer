import '../models/protect_camera.dart';

class CameraState {
  final List<ProtectCamera> cameras;
  final Set<String> selectedIds;

  const CameraState({this.cameras = const [], this.selectedIds = const {}});

  bool get canStartMonitoring => selectedIds.isNotEmpty;

  bool get hasPerformanceRisk => selectedIds.length > 2;

  bool get hasUnifiCameras => cameras.any((c) => c.source == CameraSource.unifi);

  bool get hasManualCameras =>
      cameras.any((c) => c.source == CameraSource.manual);

  /// Both Unifi and manual cameras are present — only then does the UI need to
  /// label each camera's source (per requirement: no distinction when there is
  /// only one type).
  bool get hasMixedSources => hasUnifiCameras && hasManualCameras;

  List<ProtectCamera> get selectedCameras =>
      cameras.where((c) => selectedIds.contains(c.id)).toList();

  CameraState copyWith({List<ProtectCamera>? cameras, Set<String>? selectedIds}) =>
      CameraState(
        cameras: cameras ?? this.cameras,
        selectedIds: selectedIds ?? this.selectedIds,
      );
}
