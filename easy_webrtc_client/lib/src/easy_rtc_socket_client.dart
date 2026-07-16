import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Минимальный WebSocket-клиент для подключения к серверу пакета
/// easy_webrtc_server. Переподключается сам с растущей задержкой при
/// обрыве и автоматически перезаходит в ту же комнату.
class EasyRtcSocketClient {
  EasyRtcSocketClient({required this.serverUrl});

  final String serverUrl;

  WebSocketChannel? _channel;
  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();

  String? _userId;
  String? _roomId;
  bool _isDisposed = false;

  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const int _maxReconnectDelaySeconds = 15;

  Stream<Map<String, dynamic>> get events => _eventsController.stream;
  bool get isConnected => _channel != null;

  Future<void> connectAndJoinRoom({
    required String userId,
    required String roomId,
  }) async {
    _userId = userId;
    _roomId = roomId;
    _connect();
  }

  void _connect() {
    if (_isDisposed) return;

    final uri = Uri.parse('$serverUrl?userId=$_userId');
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (raw) {
        try {
          _eventsController.add(
            jsonDecode(raw as String) as Map<String, dynamic>,
          );
        } catch (_) {
          // некорректный JSON от сервера — молча игнорируем
        }
      },
      onDone: _handleDrop,
      onError: (Object _) => _handleDrop(),
    );

    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();

    send({'type': 'join_room', 'roomId': _roomId});
  }

  void _handleDrop() {
    _channel = null;
    if (_isDisposed || _userId == null)
      return; // осознанный disconnect — не переподключаемся

    _reconnectTimer?.cancel();
    _reconnectAttempt++;
    final delay = min(3 * _reconnectAttempt, _maxReconnectDelaySeconds);
    _reconnectTimer = Timer(Duration(seconds: delay), _connect);
  }

  void send(Map<String, dynamic> event) {
    _channel?.sink.add(jsonEncode(event));
  }

  Future<void> disconnect() async {
    _userId = null; // запрещаем автопереподключение после осознанного выхода
    _reconnectTimer?.cancel();
    send({'type': 'leave_room'});
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await disconnect();
    await _eventsController.close();
  }
}
