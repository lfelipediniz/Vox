import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:voxaccess/services/chat_session_manager.dart';

class FloatingBubbleWidget extends StatefulWidget {
  const FloatingBubbleWidget({super.key});

  @override
  State<FloatingBubbleWidget> createState() => _FloatingBubbleWidgetState();
}

class _FloatingBubbleWidgetState extends State<FloatingBubbleWidget> {
  final double _bubbleSize = 60;
  final Color _bubbleColor = const Color(0xFF2196F3);

  final ChatSessionManager _chatManager = ChatSessionManager.instance;
  StreamSubscription<ChatMessage>? _messagesSub;
  StreamSubscription<bool>? _canSendSub;
  StreamSubscription<ChatConnectionStatus>? _statusSub;

  Offset _position = Offset.zero;
  bool _positionInitialized = false;
  bool _isDragging = false;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _transcribedText = '';
  String? _errorMessage;
  String? _lastIncomingText;
  bool _canSendMessage = false;
  ChatConnectionStatus _connectionStatus = ChatConnectionStatus.disconnected;
  bool _isPreparingSession = true;

  @override
  void initState() {
    super.initState();
    _initializeSpeechEngine();
    _prepareChatSession();
  }

  Future<void> _initializeSpeechEngine() async {
    try {
      final available = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
        debugLogging: false,
      );
      if (!mounted) return;
      setState(() {
        _speechAvailable = available;
        if (!available) {
          _errorMessage = 'Reconhecimento de voz indisponível.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _errorMessage = 'Erro ao inicializar o microfone.';
      });
    }
  }

  Future<void> _prepareChatSession() async {
    try {
      await _chatManager.initialize();
      await _chatManager.ensureSession();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Não foi possível conectar ao chat. Tente novamente.';
      });
    }

    if (!mounted) return;

    _statusSub = _chatManager.connectionStatusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        _connectionStatus = status;
      });
    });

    _canSendSub = _chatManager.canSendStream.listen((canSend) {
      if (!mounted) return;
      setState(() {
        _canSendMessage = canSend;
      });
    });

    final myUserId = _chatManager.userId;
    _messagesSub = _chatManager.messagesStream.listen((message) {
      if (!mounted) return;
      if (message.userId != myUserId) {
        setState(() {
          _lastIncomingText = message.text;
        });
      }
    });

    setState(() {
      _connectionStatus = _chatManager.currentStatus;
      _canSendMessage = _chatManager.canSendValue;
      _isPreparingSession = false;
    });
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'done' || status == 'notListening') {
      setState(() {
        _isListening = false;
      });
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _errorMessage = error.errorMsg;
    });
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    if (result.isGranted) return true;
    if (mounted) {
      setState(() {
        _errorMessage = 'Permissão de microfone necessária para gravar áudio.';
      });
    }
    return false;
  }

  Future<void> _startListening() async {
    if (_isDragging) return;
    if (!await _ensureMicPermission()) return;

    if (!_chatManager.canSendValue) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Aguarde a resposta antes de enviar outra mensagem.';
        });
      }
      return;
    }

    final isReady = await _ensureSessionReady();
    if (!isReady) {
      return;
    }

    if (!_speechAvailable) {
      await _initializeSpeechEngine();
      if (!_speechAvailable) return;
    }

    try {
      await _speech.stop();
      await _speech.cancel();
      await _speech.listen(
        onResult: _onSpeechResult,
        listenMode: stt.ListenMode.dictation,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(minutes: 1),
        partialResults: true,
        cancelOnError: true,
      );
      if (!mounted) return;
      setState(() {
        _isListening = true;
        _transcribedText = '';
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _errorMessage = 'Não foi possível iniciar a gravação.';
      });
    }
  }

  Future<void> _stopListening({bool canceled = false}) async {
    if (_speech.isListening) {
      if (canceled) {
        await _speech.cancel();
      } else {
        await _speech.stop();
      }
    }
    if (!mounted) return;
    setState(() {
      _isListening = false;
    });
    if (!canceled && _transcribedText.isNotEmpty) {
      await _submitCapturedText(_transcribedText);
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      _transcribedText = result.recognizedWords;
    });
  }

  Future<bool> _ensureSessionReady() async {
    try {
      await _chatManager.ensureSession();
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _errorMessage = 'Erro ao conectar ao servidor. Confira sua conexão e tente novamente.';
      });
      return false;
    }
  }

  Future<void> _submitCapturedText(String text) async {
    final sanitized = text.trim();
    if (sanitized.isEmpty) {
      return;
    }

    try {
      await _chatManager.sendMessage(sanitized);
      if (!mounted) return;
      setState(() {
        _transcribedText = '';
        if (sanitized.toLowerCase() == 'done') {
          _lastIncomingText = 'Conversa encerrada. Toque e segure para iniciar outra sessão';
        } else {
          _lastIncomingText = null;
        }
      });
    } on ChatTurnViolationException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
      });
    } on ChatSendException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Falha inesperada ao enviar a mensagem.';
      });
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _speech.cancel();
    _messagesSub?.cancel();
    _canSendSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  String _statusLabel(ChatConnectionStatus status) {
    switch (status) {
      case ChatConnectionStatus.connected:
        return 'Conectado';
      case ChatConnectionStatus.connecting:
        return 'Conectando…';
      case ChatConnectionStatus.error:
        return 'Erro de conexão';
      case ChatConnectionStatus.disconnected:
        return _isPreparingSession ? 'Preparando…' : 'Desconectado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double maxX = math.max(0.0, screenSize.width - _bubbleSize);
    final double maxY = math.max(0.0, screenSize.height - _bubbleSize);

    if (!_positionInitialized && screenSize != Size.zero) {
      Future.microtask(() {
        if (!mounted) return;
        setState(() {
          _position = Offset(maxX / 2, maxY / 2);
          _positionInitialized = true;
        });
      });
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 32),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _statusLabel(_connectionStatus),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (_transcribedText.isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(left: 16, right: 16, bottom: 40),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(16),
                ),
                width: math.min(screenSize.width - 32, 420),
                constraints: BoxConstraints(
                  minHeight: 72,
                  maxHeight: screenSize.height * 0.5,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      _transcribedText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_lastIncomingText != null && _lastIncomingText!.isNotEmpty)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: _transcribedText.isNotEmpty ? 120 : 40,
                  ),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  width: math.min(screenSize.width - 32, 420),
                  child: Text(
                    _lastIncomingText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          if (_errorMessage != null && _errorMessage!.isNotEmpty)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 48, left: 24, right: 24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 18),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: _position.dy.clamp(0.0, maxY),
            left: _position.dx.clamp(0.0, maxX),
            child: GestureDetector(
              onPanStart: (_) {
                setState(() {
                  _isDragging = true;
                  _errorMessage = null;
                });
              },
              onPanUpdate: (details) {
                setState(() {
                  double newX = _position.dx + details.delta.dx;
                  double newY = _position.dy + details.delta.dy;
                  newX = newX.clamp(0.0, maxX);
                  newY = newY.clamp(0.0, maxY);
                  _position = Offset(newX, newY);
                });
              },
              onPanEnd: (_) {
                Future.delayed(const Duration(milliseconds: 80), () {
                  if (mounted) {
                    setState(() {
                      _isDragging = false;
                    });
                  }
                });
              },
              onTap: () {
                if (_isListening) {
                  _stopListening();
                }
              },
              onLongPressStart: (_) => _startListening(),
              onLongPressEnd: (_) => _stopListening(),
              onLongPressCancel: () => _stopListening(canceled: true),
              child: Container(
                width: _bubbleSize,
                height: _bubbleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _canSendMessage
                        ? <Color>[
                            _bubbleColor,
                            _bubbleColor.withOpacity(0.75),
                          ]
                        : <Color>[
                            Colors.grey.shade600,
                            Colors.grey.shade400,
                          ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_canSendMessage ? _bubbleColor : Colors.grey).withOpacity(0.45),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _isListening
                      ? Icons.mic
                      : (_canSendMessage ? Icons.psychology : Icons.lock_clock),
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
