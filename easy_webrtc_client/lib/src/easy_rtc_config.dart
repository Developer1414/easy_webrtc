/// Конфигурация WebRTC-медиасессии: что запрашивать у устройства и в
/// каком состоянии камера/микрофон должны быть сразу после подключения.
class EasyRtcConfig {
  const EasyRtcConfig({
    this.requestAudio = true,
    this.requestVideo = false,
    this.cameraStartsOn = false,
    this.microphoneStartsOn = true,
    this.iceServers = const [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  });

  /// Захватывать ли микрофон при подключении
  final bool requestAudio;

  /// Захватывать ли камеру при подключении
  final bool requestVideo;

  /// Включена ли камера сразу после подключения
  final bool cameraStartsOn;

  /// Включен ли микрофон сразу после подключения
  final bool microphoneStartsOn;

  /// ICE-серверы (STUN/TURN). По умолчанию — публичный Google STUN,
  /// которого достаточно для большинства прямых соединений, но НЕ
  /// достаточно, если оба участника за симметричным NAT — тогда нужен
  /// свой TURN-сервер.
  final List<Map<String, dynamic>> iceServers;
}