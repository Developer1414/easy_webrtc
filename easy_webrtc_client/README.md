# easy_webrtc_client

Простой и мощный WebRTC-звонок для Flutter. Один класс `EasyRtcCall` —
WebSocket-подключение, сигналинг и медиасессия под капотом.

## Установка

```yaml
dependencies:
  easy_webrtc_client:
    git:
      url: https://github.com/<твой-юзернейм>/easy_webrtc.git
      path: easy_webrtc_client
```

## Быстрый старт

```dart
final call = EasyRtcCall(serverUrl: 'ws://localhost:8080/ws');

@override
void initState() {
  super.initState();
  call.addListener(() => setState(() {}));
  call.onPartnerLeft = () { /* показать уведомление */ };
  call.join(userId: myUserId, roomId: roomId);
}

@override
Widget build(BuildContext context) {
  return Column(
    children: [
      if (call.remoteVideo != null) call.remoteVideo!,
      ElevatedButton(onPressed: call.toggleCamera, child: Text('Камера')),
      ElevatedButton(onPressed: call.toggleMicrophone, child: Text('Микрофон')),
      ElevatedButton(onPressed: call.hangUp, child: Text('Завершить')),
    ],
  );
}

@override
void dispose() {
  call.dispose();
  super.dispose();
}
```

## API

| Поле/метод | Описание |
|---|---|
| `join({userId, roomId})` | Подключиться и войти в комнату |
| `isReady` | Локальные медиа захвачены, готово к звонку |
| `isCallActive` | WebRTC-соединение с партнёром установлено |
| `isCameraOn` / `isMicrophoneOn` | Наше состояние |
| `isPartnerCameraOn` / `isPartnerMicrophoneOn` | Состояние партнёра |
| `localVideo` / `remoteVideo` | Готовые `Widget?` для рендера |
| `toggleCamera()` / `toggleMicrophone()` | Переключение |
| `hangUp()` | Завершить звонок |
| `onPartnerLeft` | Колбэк ухода партнёра |

## Продвинутое использование

Если нужен свой транспорт сигналинга вместо WebSocket — реализуй
`EasyRtcSignaling` и используй `EasyRtcSession` напрямую вместо
`EasyRtcCall`.