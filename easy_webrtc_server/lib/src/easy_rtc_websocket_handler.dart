import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'in_memory_room_store.dart';
import 'room_store.dart';

/// Готовый WebSocket-обработчик сигналинга для WebRTC-звонков.
/// Монтируется как обычный shelf-роут:
/// ```dart
/// final rtc = EasyRtcWebSocketHandler();
/// router.get('/ws', rtc.handler);
/// ```
///
/// Протокол (JSON-сообщения):
/// - Клиент → сервер: `join_room {roomId}`, `leave_room`,
///   `webrtc_sdp`, `webrtc_ice`, `webrtc_camera_toggled`,
///   `webrtc_microphone_toggled` (все `webrtc_*` ретранслируются
///   партнёру как есть, сервер не разбирает их содержимое)
/// - Сервер → клиент: `room_ready {isInitiator}`, `partner_left`,
///   плюс всё, что ретранслируется от партнёра
class EasyRtcWebSocketHandler {
  EasyRtcWebSocketHandler({RoomStore? roomStore, this.resolveUserId})
      : roomStore = roomStore ?? InMemoryRoomStore();

  final RoomStore roomStore;

  /// Как достать userId из входящего запроса. По умолчанию — из
  /// query-параметра `?userId=...`. Передай свою функцию, если нужно
  /// доставать его из проверенного auth-токена вместо голого параметра —
  /// например, провалидировать JWT из заголовка и вернуть userId из него.
  final FutureOr<String?> Function(Request request)? resolveUserId;

  final Map<String, WebSocketChannel> _sockets = {};

  static const _relayedEventTypes = {
    'webrtc_sdp',
    'webrtc_ice',
    'webrtc_camera_toggled',
    'webrtc_microphone_toggled',
  };

  /// Shelf-хендлер для монтирования на роут (обычно `GET /ws`)
  Handler get handler => _handle;

  FutureOr<Response> _handle(Request request) async {
    final userId = resolveUserId != null
        ? await resolveUserId!(request)
        : request.url.queryParameters['userId'];

    if (userId == null || userId.isEmpty) {
      return Response.forbidden('userId не определён для WebSocket-соединения');
    }

    return webSocketHandler((WebSocketChannel webSocket, String? protocol) {
      _sockets[userId] = webSocket;

      webSocket.stream.listen(
        (raw) => _handleMessage(userId, raw),
        onDone: () => _handleDisconnect(userId),
        onError: (Object _) => _handleDisconnect(userId),
      );
    })(request);
  }

  void _sendTo(String userId, Map<String, dynamic> event) {
    _sockets[userId]?.sink.add(jsonEncode(event));
  }

  Future<void> _handleMessage(String userId, dynamic raw) async {
    final Map<String, dynamic> event;
    try {
      event = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = event['type'] as String?;
    if (type == null) return;

    if (type == 'join_room') {
      final roomId = event['roomId'] as String?;
      if (roomId == null || roomId.isEmpty) return;

      final others = await roomStore.join(roomId, userId);
      if (others.isNotEmpty) {
        _sendTo(userId, {'type': 'room_ready', 'isInitiator': true});
        for (final otherId in others) {
          _sendTo(otherId, {'type': 'room_ready', 'isInitiator': false});
        }
      }
      return;
    }

    if (type == 'leave_room') {
      await _handleDisconnect(userId);
      return;
    }

    if (_relayedEventTypes.contains(type)) {
      final roomId = await roomStore.roomOf(userId);
      if (roomId == null) return;
      final others = (await roomStore.membersOf(roomId)).where((id) => id != userId);
      for (final otherId in others) {
        _sendTo(otherId, event);
      }
    }
  }

  Future<void> _handleDisconnect(String userId) async {
    _sockets.remove(userId);
    final remaining = await roomStore.leave(userId);
    if (remaining != null) {
      for (final otherId in remaining) {
        _sendTo(otherId, {'type': 'partner_left'});
      }
    }
  }
}