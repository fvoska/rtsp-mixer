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

/// Convert an RTSPS URL (from the Protect API) to plain RTSP.
/// rtsps://host:7441/alias?enableSrtp → rtsp://host:7447/alias
String rtspsToRtsp(String rtspsUrl) {
  var url = rtspsUrl.replaceFirst('rtsps://', 'rtsp://');
  url = url.replaceFirst(':7441/', ':7447/');
  url = url.replaceFirst(RegExp(r'\?enableSrtp$'), '');
  return url;
}

/// Returns the appropriate URL based on the useRtsp setting.
String resolveStreamUrl(String rtspsUrl, {required bool useRtsp}) {
  return useRtsp ? rtspsToRtsp(rtspsUrl) : rtspsUrl;
}
