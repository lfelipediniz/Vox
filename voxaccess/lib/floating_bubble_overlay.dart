import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class FloatingBubbleWidget extends StatefulWidget {
  const FloatingBubbleWidget({super.key});

  @override
  State<FloatingBubbleWidget> createState() => _FloatingBubbleWidgetState();
}

class _FloatingBubbleWidgetState extends State<FloatingBubbleWidget> {
  bool _showModal = false;
  final Color _bubbleColor = const Color(0xFF2196F3);
  bool _isDragging = false;
  Offset _position = Offset.zero;
  final double bubbleSize = 60;
  bool _positionInitialized = false;

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double maxX = math.max(0.0, screenSize.width - bubbleSize);
    final double maxY = math.max(0.0, screenSize.height - bubbleSize);

    if (!_positionInitialized && screenSize != Size.zero) {
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _position = Offset(maxX / 2, maxY / 2);
            _positionInitialized = true;
          });
        }
      });
    }
    
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Stack(
        children: [
          // Bubble principal (sempre visível)
          if (!_showModal)
            Positioned(
              top: _position.dy.clamp(0.0, maxY),
              left: _position.dx.clamp(0.0, maxX),
              child: GestureDetector(
                onPanStart: (_) {
                  setState(() {
                    _isDragging = true;
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    // Calcula nova posição
                    double newX = _position.dx + details.delta.dx;
                    double newY = _position.dy + details.delta.dy;
                    
                    // Aplica limites nas bordas da tela
                    newX = newX.clamp(0.0, maxX);
                    newY = newY.clamp(0.0, maxY);
                    
                    _position = Offset(newX, newY);
                  });
                },
                onPanEnd: (_) {
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) {
                      setState(() {
                        _isDragging = false;
                      });
                    }
                  });
                },
                onTap: () {
                  if (!_isDragging) {
                    setState(() {
                      _showModal = true;
                    });
                    FlutterOverlayWindow.shareData('modal_opened');
                  }
                },
                child: Container(
                  width: bubbleSize,
                  height: bubbleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _bubbleColor,
                        _bubbleColor.withOpacity(0.8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _bubbleColor.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.psychology,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          
          // Modal em tela cheia
          if (_showModal && !_isDragging)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showModal = false;
                  });
                },
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {}, // Previne fechar ao clicar no modal
                      child: Container(
                        width: 320,
                        height: 500,
                        margin: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Header do modal
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _bubbleColor,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.psychology,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Assistente IA',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _showModal = false;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            // Corpo do modal (vazio por enquanto)
                            const Expanded(
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.construction,
                                        size: 64,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'Modal em desenvolvimento',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Os elementos serão implementados aqui',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
