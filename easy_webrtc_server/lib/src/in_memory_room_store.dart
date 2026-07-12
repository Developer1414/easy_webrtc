import 'room_store.dart';

/// Реализация RoomStore в памяти процесса. Подходит для одного
/// инстанса сервера — этого достаточно для подавляющего большинства
/// проектов на старте.
class InMemoryRoomStore implements RoomStore {
  final Map<String, Set<String>> _roomToUserIds = {};
  final Map<String, String> _userIdToRoom = {};

  @override
  Future<List<String>> join(String roomId, String userId) async {
    await leave(userId);

    final members = _roomToUserIds.putIfAbsent(roomId, () => <String>{});
    final others = members.toList(growable: false);

    members.add(userId);
    _userIdToRoom[userId] = roomId;

    return others;
  }

  @override
  Future<List<String>?> leave(String userId) async {
    final roomId = _userIdToRoom.remove(userId);
    if (roomId == null) return null;

    final members = _roomToUserIds[roomId];
    if (members == null) return null;

    members.remove(userId);
    final remaining = members.toList(growable: false);

    if (members.isEmpty) {
      _roomToUserIds.remove(roomId);
    }

    return remaining;
  }

  @override
  Future<String?> roomOf(String userId) async => _userIdToRoom[userId];

  @override
  Future<List<String>> membersOf(String roomId) async =>
      _roomToUserIds[roomId]?.toList(growable: false) ?? const [];
}