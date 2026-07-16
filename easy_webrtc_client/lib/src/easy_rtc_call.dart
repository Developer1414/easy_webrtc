import 'package:flutter/widgets.dart';

import 'easy_rtc_config.dart';
import 'easy_rtc_network_quality.dart';
import 'easy_rtc_session.dart';
import 'easy_rtc_socket_client.dart';
import 'easy_rtc_socket_signaling.dart';

/// Единственный класс, который нужен для большинства сценариев.
///
/// ```dart
/// final call = EasyRtcCall(serverUrl: 'ws://localhost:8080/rtc');
/// await call.join(userId: myUserId, roomId: roomId);
/// call.addListener(() => setState(() {}));
/// // call.localVideo, call.remoteVideo, call.isCameraOn,
/// // call.toggleCamera(), call.networkQuality, ...
/// ```
class EasyRtcCall extends ChangeNotifier {
  EasyRtcCall({required this.serverUrl, this.config = const EasyRtcConfig()});

  final String serverUrl;
  final EasyRtcConfig config;

  EasyRtcSocketClient? _socketClient;
  EasyRtcSocketSignaling? _signaling;
  EasyRtcSession? _session;

  bool _isJoining = false;

  /// Партнёр покинул звонок
  void Function()? onPartnerLeft;

  bool get isReady => _session?.isConnected ?? false;
  bool get isCallActive => _session?.isFullyConnected ?? false;

  bool get isCameraOn => _session?.isCameraOn ?? false;
  bool get isMicrophoneOn => _session?.isMicrophoneOn ?? false;
  bool get isVolumeOn => _session?.isVolumeOn ?? true;

  bool get isPartnerCameraOn => _session?.isRemoteCameraOn ?? false;
  bool get isPartnerMicrophoneOn => _session?.isRemoteMicrophoneOn ?? true;
  bool get isPartnerVolumeOn => _session?.isRemoteVolumeOn ?? true;

  /// Качество связи с партнёром (good по умолчанию, пока не доказано
  /// обратное)
  NetworkQuality get networkQuality =>
      _session?.networkQuality ?? NetworkQuality.good;

  /// Шорткат для UI: показать плашку "нестабильное соединение"
  bool get hasConnectionIssues => networkQuality != NetworkQuality.good;

  Widget? get localVideo => _session?.localVideo;
  Widget get remoteMediaView =>
      _session?.remoteMediaView ?? const SizedBox.shrink();

  /// Подключается к серверу, заходит в комнату [roomId] и захватывает
  /// локальные медиа. Вызови один раз в initState экрана звонка.
  Future<void> join({required String userId, required String roomId}) async {
    if (_isJoining || isReady) return;
    _isJoining = true;

    try {
      _socketClient = EasyRtcSocketClient(serverUrl: serverUrl);
      await _socketClient!.connectAndJoinRoom(userId: userId, roomId: roomId);

      _signaling = EasyRtcSocketSignaling(_socketClient!);
      _signaling!.onPartnerLeft = () => onPartnerLeft?.call();

      _session = EasyRtcSession(signaling: _signaling!, config: config);
      _session!.addListener(notifyListeners);

      await _session!.connect();

      _signaling!.onRoomReady = (isInitiator) {
        if (isInitiator) _session!.startCall();
      };
    } finally {
      _isJoining = false;
      notifyListeners();
    }
  }

  void toggleCamera() => _session?.toggleCamera();
  void toggleMicrophone() => _session?.toggleMicrophone();
  void toggleVolume() => _session?.toggleVolume();

  Future<void> hangUp() async {
    await _session?.endCall();
    await _socketClient?.disconnect();
  }

  @override
  void dispose() {
    _session?.removeListener(notifyListeners);
    _session?.dispose();
    _socketClient?.dispose();
    super.dispose();
  }
}
