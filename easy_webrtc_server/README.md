# easy_webrtc_server

Готовый WebSocket-сигналинг-сервер для WebRTC-звонков на базе shelf.
Один класс — комнаты, релей SDP/ICE, уведомления об уходе партнёра.

## Установка

```yaml
dependencies:
  easy_webrtc_server:
    git:
      url: https://github.com/<твой-юзернейм>/easy_webrtc.git
      path: easy_webrtc_server
```

## Быстрый старт

```dart
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:easy_webrtc_server/easy_webrtc_server.dart';

void main() async {
  final router = Router();
  final rtc = EasyRtcWebSocketHandler();

  router.get('/ws', rtc.handler);

  await shelf_io.serve(router.call, '0.0.0.0', 8080);
}
```

Клиенты подключаются на `ws://host:8080/ws?userId=...` и шлют
`{"type": "join_room", "roomId": "..."}` — остальное пакет берёт на себя.

## Своя авторизация

```dart
final rtc = EasyRtcWebSocketHandler(
  resolveUserId: (request) {
    final token = request.headers['authorization'];
    return myAuthService.verifyAndGetUserId(token);
  },
);
```

## Своё хранилище комнат

По умолчанию — в памяти процесса (`InMemoryRoomStore`). Для нескольких
инстансов сервера реализуй `RoomStore` поверх общего стора. Учти: сама
ретрансляция сообщений всё равно требует, чтобы оба участника были на
одном процессе (sticky sessions на балансировщике) — это ограничение
текущей версии пакета.