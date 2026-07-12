import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Минимальный WebSocket-клиент для подключения к серверу пакета
/// easy_webrtc_server: подключение, вход в комнату, обмен JSON-событиями.
class EasyRtcSocketClient {
  EasyRtcSocketClient({required this.serverUrl});

  /// Например: 'ws://localhost:8080/ws' в разработке,
  /// 'wss://api.example.com/ws' в проде
  final String serverUrl;

  WebSocketChannel? _channel;
  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventsController.stream;
  bool get isConnected => _channel != null;

  /// Подключается к серверу и сразу входит в указанную комнату.
  /// [userId] должен быть уникален для текущего пользователя.
  Future<void> connectAndJoinRoom({
    required String userId,
    required String roomId,
  }) async {
    final uri = Uri.parse('$serverUrl?userId=$userId');
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (raw) {
        try {
          _eventsController.add(jsonDecode(raw as String) as Map<String, dynamic>);
        } catch (_) {
          // некорректный JSON от сервера — молча игнорируем
        }
      },
      onDone: () {},
      onError: (Object _) {},
    );

    send({'type': 'join_room', 'roomId': roomId});
  }

  void send(Map<String, dynamic> event) {
    _channel?.sink.add(jsonEncode(event));
  }

  Future<void> disconnect() async {
    send({'type': 'leave_room'});
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _eventsController.close();
  }
}