import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'easy_rtc_config.dart';
import 'easy_rtc_network_quality.dart';
import 'easy_rtc_signaling.dart';

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
    _signaling.onRemoteVolumeToggled = (isOn) {
      _isRemoteVolumeOn = isOn;
      notifyListeners();
    };
  }

  final EasyRtcSignaling _signaling;
  final EasyRtcConfig config;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStreamTrack? _localVideoTrack;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _hasVideoTrack = false;
  bool _hasAudioTrack = false;

  bool _isMicrophoneOn = true;
  bool _isCameraOn = false;
  bool _isVolumeOn = true;

  bool _isRemoteCameraOn = false;
  bool _isRemoteMicrophoneOn = true;
  bool _isRemoteVolumeOn = true;

  RTCPeerConnectionState _connectionState =
      RTCPeerConnectionState.RTCPeerConnectionStateNew;
  bool _hasEverConnected = false;

  bool get isConnected => _isConnected;
  bool get isMicrophoneOn => _isMicrophoneOn;
  bool get isCameraOn => _isCameraOn;
  bool get isVolumeOn => _isVolumeOn;

  bool get isRemoteCameraOn => _isRemoteCameraOn;
  bool get isRemoteMicrophoneOn => _isRemoteMicrophoneOn;
  bool get isRemoteVolumeOn => _isRemoteVolumeOn;

  RTCPeerConnectionState get connectionState => _connectionState;
  bool get isFullyConnected =>
      _connectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  /// Качество связи с партнёром. До первого успешного подключения
  /// всегда good — чтобы не путать "ещё не подключились" с "испортилось".
  NetworkQuality get networkQuality {
    if (!_hasEverConnected) return NetworkQuality.good;

    switch (_connectionState) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return NetworkQuality.good;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return NetworkQuality.unstable;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return NetworkQuality.lost;
      default:
        return NetworkQuality.good;
    }
  }

  Widget? get localVideo => _hasVideoTrack
      ? RTCVideoView(
          _localRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          mirror: true,
        )
      : null;

  Widget get remoteMediaView {
    if (_remoteRenderer.srcObject == null) {
      return const SizedBox.shrink();
    }

    return Opacity(
      opacity: _isRemoteCameraOn ? 1.0 : 0.0,
      child: RTCVideoView(
        _remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }

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
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _hasEverConnected = true;
        }
        notifyListeners();
      };

      _hasVideoTrack = config.requestVideo;
      _hasAudioTrack = config.requestAudio;

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': config.requestAudio,
        'video': false,
      });

      _isCameraOn = false;
      _isMicrophoneOn = config.microphoneStartsOn && _hasAudioTrack;

      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = false;
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

    // Применяем уже выставленное локальное состояние "звук выключен" к
    // только что пришедшему треку — важно, если toggleVolume() был
    // вызван ДО того, как партнёр реально прислал медиапоток.
    for (final track in _remoteStream!.getAudioTracks()) {
      track.enabled = _isVolumeOn;
    }

    _isRemoteCameraOn = _remoteStream!.getVideoTracks().isNotEmpty;
    _remoteRenderer.srcObject = _remoteStream;
    notifyListeners();
  }

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

  Future<void> toggleCamera() async {
    if (_localStream == null || _peerConnection == null) return;

    if (_localVideoTrack == null) {
      final videoStream = await navigator.mediaDevices.getUserMedia({
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
      });

      final videoTracks = videoStream.getVideoTracks();
      if (videoTracks.isEmpty) return;

      _localVideoTrack = videoTracks.first;
      await _peerConnection!.addTrack(_localVideoTrack!, videoStream);
      _hasVideoTrack = true;
    }

    _isCameraOn = !_isCameraOn;
    _localVideoTrack!.enabled = _isCameraOn;

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

  /// Выключает воспроизведение звука ПАРТНЁРА локально — на его трек
  /// это никак не влияет, он продолжает слать аудио как обычно.
  void toggleVolume() {
    _isVolumeOn = !_isVolumeOn;
    for (final track
        in _remoteStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = _isVolumeOn;
    }
    _signaling.sendVolumeToggled(_isVolumeOn);
    notifyListeners();
  }

  Future<void> endCall() async {
    await _releaseResources();
    notifyListeners();
  }

  Future<void> _releaseResources() async {
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _peerConnection?.close();

    _localStream = null;
    _remoteStream = null;
    _localVideoTrack = null;
    _isCameraOn = false;
    _isRemoteCameraOn = false;
    _isConnected = false;

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
  }

  @override
  void dispose() {
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _peerConnection?.close();
    _peerConnection?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signaling.dispose();

    super.dispose();
  }
}
