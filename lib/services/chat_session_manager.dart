import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

const _webSocketBaseUrl = 'wss://websocketapi-feyu.onrender.com/ws';
const _userIdPrefsKey = 'chat_user_id';
const _roomIdPrefsKey = 'chat_active_room_id';
const _hardcodedRoomId = '1';

/// Represents the current state of the connection with the chat WebSocket.
enum ChatConnectionStatus { disconnected, connecting, connected, error }

/// Data model for chat messages exchanged through the WebSocket.
class ChatMessage {
  const ChatMessage({
    required this.roomId,
    required this.userId,
    required this.text,
    required this.timestamp,
  });

  final String roomId;
  final String userId;
  final String text;
  final int timestamp;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    String? _readString(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      return value.toString();
    }

    return ChatMessage(
      roomId: _readString(json['room_id']) ?? _readString(json['roomId']) ?? '',
      userId: _readString(json['user_id']) ?? _readString(json['userId']) ?? '',
      text:
          _readString(json['text']) ??
          _readString(json['message']) ??
          _readString(json['content']) ??
          '',
      timestamp: (json['ts'] is String)
          ? int.tryParse(json['ts'] as String) ?? 0
          : (json['ts'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'room_id': roomId,
      'user_id': userId,
      'text': text,
      'ts': timestamp,
    };
  }
}

/// Base class for chat related exceptions.
class ChatException implements Exception {
  const ChatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when attempting to send a message without respecting the turn rule.
class ChatTurnViolationException extends ChatException {
  const ChatTurnViolationException()
    : super('Aguarde a resposta antes de enviar outra mensagem.');
}

/// Thrown when a message could not be delivered.
class ChatSendException extends ChatException {
  const ChatSendException(super.message);
}

/// Coordinates WebSocket connectivity, message flow, and turn-taking logic.
class ChatSessionManager {
  ChatSessionManager._internal();

  static final ChatSessionManager instance = ChatSessionManager._internal();

  final StreamController<ChatMessage> _messagesController =
      StreamController<ChatMessage>.broadcast();
  final StreamController<bool> _canSendController =
      StreamController<bool>.broadcast();
  final StreamController<ChatConnectionStatus> _statusController =
      StreamController<ChatConnectionStatus>.broadcast();
  final StreamController<Object?> _errorController =
      StreamController<Object?>.broadcast();

  final Random _random = Random();

  SharedPreferences? _prefs;
  String? _userId;
  String? _roomId;
  bool _awaitingTurn = false;
  bool _canSend = false;
  bool _shouldReconnect = false;
  bool _isConnecting = false;
  int _retryAttempt = 0;
  ChatConnectionStatus _status = ChatConnectionStatus.disconnected;
  Object? _lastError;
  int _pendingPlaybackLocks = 0;
  String? _lastSentMessageText;
  int? _lastSentTimestampMs;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _reconnectTimer;
  Completer<void>? _connectionCompleter;

  static const List<Duration> _backoffSteps = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];

  bool _initialized = false;

  /// Stream with all messages received from the WebSocket.
  Stream<ChatMessage> get messagesStream => _messagesController.stream;

  /// Stream that informs whether the user can send a new message respecting the turn rule.
  Stream<bool> get canSendStream => _canSendController.stream;

  /// Stream that exposes the current connection status.
  Stream<ChatConnectionStatus> get connectionStatusStream =>
      _statusController.stream;

  /// Stream with raw connection errors for debugging/logging purposes.
  Stream<Object?> get errorsStream => _errorController.stream;

  /// Convenience getter for the current connection status.
  ChatConnectionStatus get currentStatus => _status;

  /// Whether the user can currently send a message.
  bool get canSendValue => _canSend;

  /// Active room identifier, if any.
  String? get currentRoomId => _roomId;

  /// User identifier persisted across installs.
  String get userId {
    if (_userId == null) {
      throw StateError(
        'ChatSessionManager.initialize() must be called before accessing userId.',
      );
    }
    return _userId!;
  }

  Object? get lastError => _lastError;

  /// Ensures internal state and persistence are ready for use.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _prefs ??= await SharedPreferences.getInstance();
    final storedUserId = _prefs!.getString(_userIdPrefsKey);
    if (storedUserId == null || storedUserId.isEmpty) {
      final generated = _generateUserId();
      await _prefs!.setString(_userIdPrefsKey, generated);
      _userId = generated;
    } else {
      _userId = storedUserId;
    }
    _roomId = _hardcodedRoomId;
    await _prefs!.setString(_roomIdPrefsKey, _hardcodedRoomId);
    _initialized = true;
    _updateCanSendValue();
  }

  /// Guarantees there is an active room and connection, reusing the previous room whenever possible.
  Future<String> ensureSession({String? preferredRoomId}) async {
    await initialize();

    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      await _connectionCompleter!.future;
      return _roomId ?? preferredRoomId ?? _createRoomId();
    }

    if (_roomId == null) {
      await _setRoomId(preferredRoomId ?? _createRoomId());
    }

    if (_channel != null) {
      return _roomId!;
    }

    _connectionCompleter = Completer<void>();
    _shouldReconnect = true;
    await _openChannel();
    await _connectionCompleter!.future;
    return _roomId!;
  }

  /// Sends a message respecting the current turn-taking restrictions.
  Future<void> sendMessage(String text) async {
    await initialize();
    final sanitized = text.trim();
    if (sanitized.isEmpty) {
      throw const ChatSendException('A mensagem não pode ser vazia.');
    }

    if (_awaitingTurn || _pendingPlaybackLocks > 0) {
      throw const ChatTurnViolationException();
    }

    await ensureSession();

    if (_status != ChatConnectionStatus.connected || _channel == null) {
      throw const ChatSendException('Conexão indisponível no momento.');
    }

    final outgoing = ChatMessage(
      roomId: _roomId!,
      userId: userId,
      text: sanitized,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      _channel!.sink.add(jsonEncode(outgoing.toJson()));
      _lastSentMessageText = outgoing.text;
      _lastSentTimestampMs = DateTime.now().millisecondsSinceEpoch;
      _awaitingTurn = true;
      _updateCanSendValue();
    } catch (error) {
      _awaitingTurn = false;
      _updateCanSendValue();
      throw ChatSendException('Falha ao enviar mensagem: $error');
    }

    if (sanitized.toLowerCase() == 'done') {
      await _finalizeConversationFromLocal();
    }
  }

  /// Manually terminates the current session, if any.
  Future<void> resetSession() async {
    await _closeCurrentConnection(clearRoom: true, shouldReconnect: false);
  }

  /// Releases resources. Should be invoked on app shutdown.
  Future<void> dispose() async {
    await _closeCurrentConnection(clearRoom: false, shouldReconnect: false);
    await _messagesController.close();
    await _canSendController.close();
    await _statusController.close();
    await _errorController.close();
  }

  Future<void> _openChannel() async {
    if (_isConnecting || _channel != null || _roomId == null) {
      return;
    }

    _isConnecting = true;
    _updateStatus(ChatConnectionStatus.connecting);
    final uri = Uri.parse('$_webSocketBaseUrl/${_roomId!}');

    try {
      final channel = IOWebSocketChannel.connect(uri);
      _channel = channel;
      _channelSubscription = channel.stream.listen(
        _handleIncomingFrame,
        onError: (Object error, StackTrace stack) =>
            _handleConnectionError(error, stack),
        onDone: _handleConnectionClosed,
        cancelOnError: true,
      );
      _retryAttempt = 0;
      _updateStatus(ChatConnectionStatus.connected);
      _updateCanSendValue();
      final completer = _connectionCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    } catch (error, stackTrace) {
      final completer = _connectionCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      _handleConnectionError(error, stackTrace, alreadyCompleted: true);
    } finally {
      _isConnecting = false;
    }
  }

  void _handleIncomingFrame(dynamic data) {
    try {
      final String rawText = data?.toString() ?? '';
      if (rawText.isEmpty) {
        return;
      }

      final int now = DateTime.now().millisecondsSinceEpoch;

      ChatMessage? decoded;
      try {
        final dynamic jsonPayload = jsonDecode(rawText);
        if (jsonPayload is Map<String, dynamic>) {
          decoded = ChatMessage.fromJson(jsonPayload);
        }
      } catch (_) {
        decoded = null;
      }

      if (decoded != null) {
        final String? localUserId = _userId;
        final bool isLocal =
            localUserId != null && decoded.userId == localUserId;

        bool isEcho = false;
        if (isLocal) {
          final String normalizedIncoming = decoded.text.trim();
          final String? normalizedLastSent = _lastSentMessageText?.trim();
          if (normalizedLastSent != null && normalizedIncoming.isNotEmpty) {
            final bool sameContent = normalizedIncoming == normalizedLastSent;
            final bool closeInTime =
                _lastSentTimestampMs != null &&
                (decoded.timestamp == 0 ||
                    (decoded.timestamp - _lastSentTimestampMs!).abs() < 5000);
            isEcho = sameContent && closeInTime;
          } else if (normalizedLastSent == null && normalizedIncoming.isEmpty) {
            isEcho = true;
          }
        }

        if (isEcho) {
          // Server simply echoed our own message; wait for the actual reply.
          return;
        }

        final ChatMessage remoteMessage = decoded.copyWith(
          userId: isLocal ? 'assistant' : decoded.userId,
          timestamp: decoded.timestamp == 0 ? now : decoded.timestamp,
        );
        _messagesController.add(remoteMessage);

        _awaitingTurn = false;
        _updateCanSendValue();
        final String normalized = remoteMessage.text.trim().toLowerCase();
        if (normalized == 'done') {
          _clearPlaybackLocks();
          _finalizeConversationFromRemote();
          return;
        }
        if (remoteMessage.text.trim().isNotEmpty) {
          _pushPlaybackLock();
        }
        return;
      }

      final bool isLikelySelfEcho =
          _lastSentMessageText != null &&
          _lastSentTimestampMs != null &&
          _lastSentMessageText == rawText &&
          (now - _lastSentTimestampMs!) < 1500;

      if (isLikelySelfEcho) {
        return;
      }

      final ChatMessage message = ChatMessage(
        roomId: _roomId ?? _hardcodedRoomId,
        userId: 'remote',
        text: rawText,
        timestamp: now,
      );

      _messagesController.add(message);

      _awaitingTurn = false;
      _updateCanSendValue();
      final String normalized = rawText.trim().toLowerCase();
      if (normalized == 'done') {
        _clearPlaybackLocks();
        _finalizeConversationFromRemote();
        return;
      }
      if (message.text.trim().isNotEmpty) {
        _pushPlaybackLock();
      }
    } catch (error, stackTrace) {
      debugPrint('Erro ao processar mensagem do WebSocket: $error');
      _errorController.add(error);
      if (kDebugMode) {
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  void _handleConnectionError(
    Object error,
    StackTrace stackTrace, {
    bool alreadyCompleted = false,
  }) {
    _lastError = error;
    _errorController.add(error);
    _updateStatus(ChatConnectionStatus.error);
    final completer = _connectionCompleter;
    if (!alreadyCompleted && completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
    _disposeChannel();
    if (_shouldReconnect && _roomId != null) {
      _scheduleReconnect();
    } else {
      _updateCanSendValue();
    }
  }

  void _handleConnectionClosed() {
    final completer = _connectionCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const ChatSendException('Conexão encerrada.'));
    }
    _disposeChannel();
    final shouldAttemptReconnect = _shouldReconnect && _roomId != null;
    _updateStatus(ChatConnectionStatus.disconnected);
    _pendingPlaybackLocks = 0;
    if (shouldAttemptReconnect) {
      _updateCanSendValue(forceValue: false);
      _scheduleReconnect();
    } else {
      _awaitingTurn = false;
      _updateCanSendValue(forceValue: true);
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _roomId == null) {
      return;
    }
    _reconnectTimer?.cancel();
    final int index = _retryAttempt.clamp(0, _backoffSteps.length - 1);
    final delay = _backoffSteps[index];
    if (_retryAttempt < _backoffSteps.length - 1) {
      _retryAttempt += 1;
    }
    _reconnectTimer = Timer(delay, () {
      if (!_shouldReconnect || _roomId == null) {
        return;
      }
      _openChannel();
    });
  }

  Future<void> _finalizeConversationFromLocal() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _closeCurrentConnection(clearRoom: true, shouldReconnect: false);
    _updateCanSendValue(forceValue: true);
  }

  Future<void> _finalizeConversationFromRemote() async {
    await _closeCurrentConnection(clearRoom: true, shouldReconnect: false);
    _updateCanSendValue(forceValue: true);
  }

  Future<void> _closeCurrentConnection({
    required bool clearRoom,
    required bool shouldReconnect,
  }) async {
    _shouldReconnect = shouldReconnect;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (_channel != null) {
      try {
        await _channel!.sink.close(ws_status.normalClosure);
      } catch (_) {
        // Ignore close exceptions - socket might already be closed.
      }
    }

    await _channelSubscription?.cancel();
    _disposeChannel();

    if (clearRoom) {
      await _setRoomId(null);
    }

    _awaitingTurn = false;
    _clearPlaybackLocks();
    _updateStatus(ChatConnectionStatus.disconnected);
    _updateCanSendValue(forceValue: !shouldReconnect);
  }

  void _disposeChannel() {
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel = null;
    _connectionCompleter = null;
  }

  Future<void> _setRoomId(String? value) async {
    _roomId = value;
    if (!_initialized) {
      return;
    }
    if (value == null) {
      await _prefs?.remove(_roomIdPrefsKey);
    } else {
      await _prefs?.setString(_roomIdPrefsKey, value);
    }
  }

  String _createRoomId() {
    return _hardcodedRoomId;
  }

  Future<void> acknowledgeRemotePlayback() async {
    if (!_initialized) {
      return;
    }
    _releasePlaybackLock();
  }

  String _generateUserId() {
    final suffix = _random
        .nextInt(0xFFFFFFFF)
        .toRadixString(16)
        .padLeft(8, '0');
    return 'user-${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  void _updateStatus(ChatConnectionStatus newStatus) {
    if (_status == newStatus) {
      return;
    }
    _status = newStatus;
    _statusController.add(_status);
  }

  void _updateCanSendValue({bool? forceValue}) {
    bool nextValue;
    if (forceValue != null) {
      nextValue = forceValue;
    } else if (_status != ChatConnectionStatus.connected) {
      nextValue = false;
    } else {
      nextValue = !_awaitingTurn && _pendingPlaybackLocks == 0;
    }

    if (_canSend == nextValue) {
      return;
    }
    _canSend = nextValue;
    _canSendController.add(_canSend);
  }

  void _pushPlaybackLock() {
    _pendingPlaybackLocks += 1;
    _updateCanSendValue();
  }

  void _releasePlaybackLock() {
    if (_pendingPlaybackLocks == 0) {
      return;
    }
    _pendingPlaybackLocks -= 1;
    if (_pendingPlaybackLocks < 0) {
      _pendingPlaybackLocks = 0;
    }
    _updateCanSendValue();
  }

  void _clearPlaybackLocks() {
    if (_pendingPlaybackLocks == 0) {
      return;
    }
    _pendingPlaybackLocks = 0;
    _updateCanSendValue();
  }
}

extension on ChatMessage {
  ChatMessage copyWith({
    String? roomId,
    String? userId,
    String? text,
    int? timestamp,
  }) {
    return ChatMessage(
      roomId: roomId ?? this.roomId,
      userId: userId ?? this.userId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
