import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'easy_rtc_signaling.dart';
import 'easy_rtc_socket_client.dart';

/// Реализация EasyRtcSignaling поверх EasyRtcSocketClient — переводит
/// события WebRTC-сессии в JSON-сообщения комнаты и обратно, по
/// протоколу, который понимает easy_webrtc_server "из коробки".
class EasyRtcSocketSignaling implements EasyRtcSignaling {
  EasyRtcSocketSignaling(this._client) {
    _subscription = _client.events.listen(_handleIncoming);
  }

  final EasyRtcSocketClient _client;
  late final StreamSubscription<Map<String, dynamic>> _subscription;

  /// Сервер сообщил, что в комнате теперь двое и можно начинать звонок.
  /// [isInitiator] — должна ли ЭТА сторона создавать offer.
  void Function(bool isInitiator)? onRoomReady;

  /// Партнёр покинул комнату / отключился
  void Function()? onPartnerLeft;

  @override
  void Function(RTCSessionDescription description)? onRemoteDescription;
  @override
  void Function(RTCIceCandidate candidate)? onRemoteIceCandidate;
  @override
  void Function(bool isOn)? onRemoteCameraToggled;
  @override
  void Function(bool isOn)? onRemoteMicrophoneToggled;

  void _handleIncoming(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'room_ready':
        onRoomReady?.call(event['isInitiator'] as bool);
      case 'partner_left':
        onPartnerLeft?.call();
      case 'webrtc_sdp':
        onRemoteDescription?.call(
          RTCSessionDescription(event['sdp'] as String, event['sdpType'] as String),
        );
      case 'webrtc_ice':
        onRemoteIceCandidate?.call(
          RTCIceCandidate(
            event['candidate'] as String,
            event['sdpMid'] as String?,
            event['sdpMLineIndex'] as int?,
          ),
        );
      case 'webrtc_camera_toggled':
        onRemoteCameraToggled?.call(event['isOn'] as bool);
      case 'webrtc_microphone_toggled':
        onRemoteMicrophoneToggled?.call(event['isOn'] as bool);
    }
  }

  @override
  void sendDescription(RTCSessionDescription description) {
    _client.send({'type': 'webrtc_sdp', 'sdp': description.sdp, 'sdpType': description.type});
  }

  @override
  void sendIceCandidate(RTCIceCandidate candidate) {
    _client.send({
      'type': 'webrtc_ice',
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  }

  @override
  void sendCameraToggled(bool isOn) =>
      _client.send({'type': 'webrtc_camera_toggled', 'isOn': isOn});

  @override
  void sendMicrophoneToggled(bool isOn) =>
      _client.send({'type': 'webrtc_microphone_toggled', 'isOn': isOn});

  @override
  void dispose() => _subscription.cancel();
}