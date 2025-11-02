import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class FloatingBubbleWidget extends StatefulWidget {
  const FloatingBubbleWidget({super.key});

  @override
  State<FloatingBubbleWidget> createState() => _FloatingBubbleWidgetState();
}

class _FloatingBubbleWidgetState extends State<FloatingBubbleWidget> {
  final double _bubbleSize = 60;
  final Color _bubbleColor = const Color(0xFF2196F3);

  Offset _position = Offset.zero;
  bool _positionInitialized = false;
  bool _isDragging = false;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _transcribedText = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeSpeechEngine();
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
      FlutterOverlayWindow.shareData(_transcribedText);
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      _transcribedText = result.recognizedWords;
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _speech.cancel();
    super.dispose();
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
          if (_isListening)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 100),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                width: math.min(screenSize.width - 64, 260),
                decoration: BoxDecoration(
                  color: _bubbleColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _bubbleColor.withOpacity(0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    Icon(Icons.mic, color: Colors.white),
                    Text(
                      'Gravando...',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
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
                    colors: [
                      _bubbleColor,
                      _bubbleColor.withOpacity(0.75),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _bubbleColor.withOpacity(0.45),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.psychology,
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
