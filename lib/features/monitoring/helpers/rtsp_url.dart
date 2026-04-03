/// Constructs unencrypted RTSP URL for a Protect camera.
/// Port 7447 is Unifi Protect's RTSP port (must be enabled per-camera).
String rtspUrl(String nvrHost, String cameraId) {
  final host =
      nvrHost.endsWith('/') ? nvrHost.substring(0, nvrHost.length - 1) : nvrHost;
  return 'rtsp://$host:7447/$cameraId';
}

/// Constructs encrypted RTSPS URL for a Protect camera.
/// Port 7441 is Unifi Protect's RTSPS port with SRTP.
String rtspsUrl(String nvrHost, String cameraId) {
  final host =
      nvrHost.endsWith('/') ? nvrHost.substring(0, nvrHost.length - 1) : nvrHost;
  return 'rtsps://$host:7441/$cameraId?enableSrtp';
}
