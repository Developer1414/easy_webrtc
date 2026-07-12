import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'easy_rtc_config.dart';
import 'easy_rtc_signaling.dart';

/// Ядро пакета: управляет PeerConnection, локальным/удалённым медиа-
/// потоками и состоянием камеры/микрофона. Не знает о комнатах или
/// пользователях — только о самом WebRTC-соединении и переданном
/// сигналинге.
class EasyRtcSession extends ChangeNotifier {
  EasyRtcSession({
    required EasyRtcSignaling signaling,
    this.config = const EasyRtcConfig(),
  }) : _signaling = signaling {
    _signaling.onRemoteDescription = _handleRemoteDescription;
    _signaling.onRemoteIceCandidate = _handleRemoteIceCandidate;
    _signaling.onRemoteCameraToggled = (isOn) {
      _isRemoteCameraOn = isOn;
      notifyListeners();
    };
    _signaling.onRemoteMicrophoneToggled = (isOn) {
      _isRemoteMicrophoneOn = isOn;
      notifyListeners();
    };
  }

  final EasyRtcSignaling _signaling;
  final EasyRtcConfig config;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _hasVideoTrack = false;
  bool _hasAudioTrack = false;

  bool _isMicrophoneOn = true;
  bool _isCameraOn = false;
  bool _isRemoteCameraOn = false;
  bool _isRemoteMicrophoneOn = true;

  RTCPeerConnectionState _connectionState =
      RTCPeerConnectionState.RTCPeerConnectionStateNew;

  bool get isConnected => _isConnected;
  bool get isMicrophoneOn => _isMicrophoneOn;
  bool get isCameraOn => _isCameraOn;
  bool get isRemoteCameraOn => _isRemoteCameraOn;
  bool get isRemoteMicrophoneOn => _isRemoteMicrophoneOn;

  RTCPeerConnectionState get connectionState => _connectionState;
  bool get isFullyConnected =>
      _connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  /// Готовый виджет с локальным превью (или null, если камера не
  /// запрошена/выключена)
  Widget? get localVideo => _hasVideoTrack
      ? RTCVideoView(
          _localRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          mirror: true,
        )
      : null;

  /// Готовый виджет с видео партнёра (или null, пока камера партнёра
  /// выключена / поток ещё не пришёл)
  Widget? get remoteVideo => _isRemoteCameraOn
      ? RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        )
      : null;

  /// Захватывает медиа согласно [config], создаёт PeerConnection.
  /// Идемпотентен: повторный вызов, пока предыдущий выполняется или уже
  /// завершился, просто выходит без побочных эффектов.
  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;

    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      _peerConnection = await createPeerConnection({
        'iceServers': config.iceServers,
      });

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        _signaling.sendIceCandidate(candidate);
      };

      _peerConnection!.onTrack = _handleRemoteTrack;
      _peerConnection!.onConnectionState = (state) {
        _connectionState = state;
        notifyListeners();
      };

      _hasVideoTrack = config.requestVideo;
      _hasAudioTrack = config.requestAudio;

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': config.requestAudio,
        'video': config.requestVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });

      _isCameraOn = config.cameraStartsOn && _hasVideoTrack;
      _isMicrophoneOn = config.microphoneStartsOn && _hasAudioTrack;

      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = _isCameraOn;
      }
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = _isMicrophoneOn;
      }

      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      _localRenderer.srcObject = _localStream;

      _isConnected = true;
      notifyListeners();
    } catch (e) {
      debugPrint('EasyRtcSession: ошибка подключения — $e');
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  void _handleRemoteTrack(RTCTrackEvent event) {
    if (event.streams.isEmpty) return;
    _remoteStream = event.streams[0];
    _remoteRenderer.srcObject = _remoteStream;
    notifyListeners();
  }

  /// Создаёт SDP offer. Вызывается стороной, инициирующей звонок.
  Future<void> startCall() async {
    if (!_requirePeerConnection('startCall')) return;
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _signaling.sendDescription(offer);
  }

  Future<void> _handleRemoteDescription(RTCSessionDescription desc) async {
    if (!_requirePeerConnection('handleRemoteDescription')) return;

    if (desc.type == 'offer') {
      await _peerConnection!.setRemoteDescription(desc);
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      _signaling.sendDescription(answer);
    } else {
      await _peerConnection!.setRemoteDescription(desc);
    }
  }

  Future<void> _handleRemoteIceCandidate(RTCIceCandidate candidate) async {
    if (!_requirePeerConnection('handleRemoteIceCandidate')) return;
    await _peerConnection!.addCandidate(candidate);
  }

  bool _requirePeerConnection(String from) {
    if (_peerConnection == null) {
      debugPrint('EasyRtcSession.$from: connect() ещё не завершён');
      return false;
    }
    return true;
  }

  void toggleCamera() {
    if (!_hasVideoTrack || _localStream == null) return;
    _isCameraOn = !_isCameraOn;
    for (final track in _localStream!.getVideoTracks()) {
      track.enabled = _isCameraOn;
    }
    _signaling.sendCameraToggled(_isCameraOn);
    notifyListeners();
  }

  void toggleMicrophone() {
    if (!_hasAudioTrack || _localStream == null) return;
    _isMicrophoneOn = !_isMicrophoneOn;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = _isMicrophoneOn;
    }
    _signaling.sendMicrophoneToggled(_isMicrophoneOn);
    notifyListeners();
  }

  /// Завершает звонок и освобождает ресурсы. Сессию после этого нужно
  /// выбросить — для нового звонка создавай новую EasyRtcSession.
  Future<void> endCall() async {
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _peerConnection?.close();

    _localStream = null;
    _remoteStream = null;
    _isCameraOn = false;
    _isRemoteCameraOn = false;
    _isConnected = false;

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_isConnected) endCall();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.dispose();
    _signaling.dispose();
    super.dispose();
  }
}