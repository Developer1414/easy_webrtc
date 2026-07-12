import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Транспорт-независимый интерфейс сигналинга. EasyRtcSession не знает,
/// КАК сообщения доставляются партнёру — только что нужно отправить или
/// получено. Пакет уже содержит готовую реализацию поверх WebSocket
/// (EasyRtcSocketSignaling) — этот интерфейс нужен, только если хочешь
/// заменить транспорт на что-то своё (Firebase, gRPC-стрим и т.д.).
abstract class EasyRtcSignaling {
  void Function(RTCSessionDescription description)? onRemoteDescription;
  void Function(RTCIceCandidate candidate)? onRemoteIceCandidate;
  void Function(bool isOn)? onRemoteCameraToggled;
  void Function(bool isOn)? onRemoteMicrophoneToggled;

  void sendDescription(RTCSessionDescription description);
  void sendIceCandidate(RTCIceCandidate candidate);
  void sendCameraToggled(bool isOn);
  void sendMicrophoneToggled(bool isOn);

  void dispose();
}