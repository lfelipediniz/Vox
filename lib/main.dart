import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'floating_bubble_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.transparent,
        child: const FloatingBubbleWidget(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoxAccess - Assistente IA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'VoxAccess'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isOverlayActive = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _checkOverlayStatus();
    
    // Escutar mensagens do overlay
    FlutterOverlayWindow.overlayListener.listen((event) {
      setState(() {
        _statusMessage = 'Evento: $event';
      });
    });
  }

  Future<void> _checkOverlayStatus() async {
    final status = await FlutterOverlayWindow.isActive();
    setState(() {
      _isOverlayActive = status;
    });
  }

  Future<void> _requestOverlayPermission() async {
    // Solicitar permissão de overlay
    final status = await Permission.systemAlertWindow.request();
    
    if (status.isGranted) {
      setState(() {
        _statusMessage = 'Permissão concedida!';
      });
    } else if (status.isDenied) {
      setState(() {
        _statusMessage = 'Permissão negada. Por favor, habilite nas configurações.';
      });
      await openAppSettings();
    }
  }

  Future<void> _toggleOverlay() async {
    final hasPermission = await Permission.systemAlertWindow.isGranted;
    
    if (!hasPermission) {
      await _requestOverlayPermission();
      return;
    }

    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        setState(() {
          _statusMessage = 'Permissão de microfone necessária para transcrever sua voz.';
        });
        return;
      }
    }

    if (_isOverlayActive) {
      await FlutterOverlayWindow.closeOverlay();
      setState(() {
        _isOverlayActive = false;
        _statusMessage = 'Bubble desativado';
      });
    } else {
      final ui.FlutterView view = ui.PlatformDispatcher.instance.views.first;
      final double devicePixelRatio = view.devicePixelRatio;
      final Size logicalSize = view.physicalSize / devicePixelRatio;

      await FlutterOverlayWindow.showOverlay(
        height: logicalSize.height.round(),
        width: logicalSize.width.round(),
        alignment: OverlayAlignment.center,
        enableDrag: true,
      );
      setState(() {
        _isOverlayActive = true;
        _statusMessage = 'Bubble ativado! Clique para abrir o assistente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ícone de IA
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.psychology,
                  size: 80,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 32),
              
              // Título
              Text(
                'Assistente IA Flutuante',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              
              // Descrição
              Text(
                'Ative o bubble flutuante para ter acesso rápido ao assistente de IA, mesmo com o app minimizado.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              
              // Status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isOverlayActive ? Colors.green.shade50 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isOverlayActive ? Colors.green : Colors.grey,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isOverlayActive ? Icons.check_circle : Icons.circle_outlined,
                      color: _isOverlayActive ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isOverlayActive ? 'Bubble Ativo' : 'Bubble Inativo',
                      style: TextStyle(
                        color: _isOverlayActive ? Colors.green.shade700 : Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Botão principal
              ElevatedButton.icon(
                onPressed: _toggleOverlay,
                icon: Icon(_isOverlayActive ? Icons.close : Icons.play_arrow),
                label: Text(_isOverlayActive ? 'Desativar Bubble' : 'Ativar Bubble'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isOverlayActive ? Colors.red : Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Botão de permissão
              if (!_isOverlayActive)
                OutlinedButton.icon(
                  onPressed: _requestOverlayPermission,
                  icon: const Icon(Icons.settings),
                  label: const Text('Verificar Permissões'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              
              const SizedBox(height: 24),
              
              // Mensagem de status
              if (_statusMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.blue.shade700),
                  ),
                ),
              
              const SizedBox(height: 32),
              
              // Instruções
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 8),
                          Text(
                            'Como usar:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text('• Clique no bubble para abrir o menu'),
                      Text('• Arraste o bubble para qualquer posição'),
                      Text('• Funciona mesmo com o app minimizado'),
                      Text('• Use os botões do menu para ações rápidas'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
