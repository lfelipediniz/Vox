import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
  Future<void> _ttsQueue = Future<void>.value();

  Offset _position = Offset.zero;
  bool _positionInitialized = false;
  bool _isDragging = false;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _ttsConfigured = false;
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
    unawaited(_configureTextToSpeech());
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
        _ttsQueue = _ttsQueue.then((_) => _handleRemoteMessage(message.text));
      }
    });

    setState(() {
      _connectionStatus = _chatManager.currentStatus;
      _canSendMessage = _chatManager.canSendValue;
      _isPreparingSession = false;
    });
  }

  Future<void> _configureTextToSpeech() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('pt-BR');
      _ttsConfigured = true;
    } catch (_) {
      try {
        await _tts.setLanguage('en-US');
        _ttsConfigured = true;
      } catch (_) {
        _ttsConfigured = false;
      }
    }
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

    if (error.errorMsg == 'error_speech_timeout' ||
        error.errorMsg == 'error_no_match') {
      final String buffered = _transcribedText.trim();
      if (buffered.isNotEmpty) {
        unawaited(_submitCapturedText(buffered));
      }
      setState(() {
        _isListening = false;
        _errorMessage = null;
      });
      return;
    }

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
      return;
    }

    final isReady = await _ensureSessionReady();
    if (!isReady) {
      return;
    }

    if (!_speechAvailable) {
      try {
        final available = await _speech.initialize(
          onStatus: _onSpeechStatus,
          onError: _onSpeechError,
          debugLogging: false,
        );
        if (!available) {
          if (mounted) {
            setState(() {
              _speechAvailable = false;
              _errorMessage =
                  'Não foi possível acessar o reconhecimento de voz agora.';
            });
          }
          return;
        }
        if (!mounted) return;
        setState(() {
          _speechAvailable = true;
          _errorMessage = null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _speechAvailable = false;
          _errorMessage = 'Falha ao preparar o reconhecimento de voz.';
        });
        return;
      }
    }

    try {
      if (_speech.isListening) {
        await _speech.stop();
      } else {
        await _speech.cancel();
      }
      await _speech.listen(
        onResult: _onSpeechResult,
        listenMode: stt.ListenMode.dictation,
        pauseFor: const Duration(seconds: 8),
        listenFor: const Duration(minutes: 2),
        partialResults: true,
        cancelOnError: true,
      );
      if (!mounted) return;
      if (!_speech.isListening) {
        setState(() {
          _isListening = false;
          _errorMessage = 'Não foi possível iniciar a gravação.';
        });
        return;
      }
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
        _speechAvailable = false;
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
        _errorMessage =
            'Erro ao conectar ao servidor. Confira sua conexão e tente novamente.';
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
        _canSendMessage = false;
        _errorMessage = null;
        if (sanitized.toLowerCase() == 'done') {
          _lastIncomingText =
              'Conversa encerrada. Toque e segure para iniciar outra sessão';
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

  Future<void> _handleRemoteMessage(String text) async {
    final sanitized = text.trim();
    if (sanitized.isNotEmpty && mounted) {
      setState(() {
        _lastIncomingText = sanitized;
      });
    }

    if (!_ttsConfigured) {
      await _configureTextToSpeech();
    }

    try {
      if (mounted) {
        setState(() {
          _isSpeaking = true;
        });
      }
      await _tts.stop();
      if (sanitized.isNotEmpty && _ttsConfigured) {
        await _tts.speak(sanitized);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage ??= 'Falha ao reproduzir a resposta recebida.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
      await _chatManager.acknowledgeRemotePlayback();
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _speech.cancel();
    _tts.stop();
    _ttsQueue = Future<void>.value();
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
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (_errorMessage != null && _errorMessage!.isNotEmpty)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 48, left: 24, right: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 18,
                    ),
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
              onLongPressStart: (_) {
                if (!_canSendMessage || _isSpeaking) {
                  return;
                }
                _startListening();
              },
              onLongPressEnd: (_) {
                _stopListening();
              },
              onLongPressCancel: () {
                _stopListening(canceled: true);
              },
              child: Container(
                width: _bubbleSize,
                height: _bubbleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _canSendMessage
                        ? <Color>[_bubbleColor, _bubbleColor.withOpacity(0.75)]
                        : <Color>[Colors.grey.shade600, Colors.grey.shade400],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_canSendMessage ? _bubbleColor : Colors.grey)
                          .withOpacity(0.45),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _isListening
                      ? Icons.mic
                      : (_canSendMessage && !_isSpeaking
                            ? Icons.psychology
                            : (_isSpeaking
                                  ? Icons.volume_up
                                  : Icons.lock_clock)),
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
