import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'capture/capture_pose.dart';
import 'capture/pose_capture_screen.dart';
import 'screens/result_screen.dart';
import 'services/analysis_api.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const AnalyseFacialeApp());
}

class AnalyseFacialeApp extends StatelessWidget {
  const AnalyseFacialeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Analyse faciale',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1ABC9C),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

/// Écran d'accueil : lance le flux de capture guidée.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _teal = Color(0xFF1ABC9C);

  void _startCapture(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaptureFlow(cameras: cameras),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.face_retouching_natural,
                    size: 96, color: _teal),
                const SizedBox(height: 24),
                const Text(
                  'Analyse faciale',
                  style:
                      TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Capturez 4 vues de votre visage pour estimer '
                  'votre sexe et votre âge.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 15),
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  onPressed: () => _startCapture(context),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Commencer la capture'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 16),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Orchestre le flux : capture des 4 vues -> envoi de la vue de face -> résultat.
class CaptureFlow extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CaptureFlow({super.key, required this.cameras});

  @override
  State<CaptureFlow> createState() => _CaptureFlowState();
}

class _CaptureFlowState extends State<CaptureFlow> {
  final _api = AnalysisApi();
  bool _analyzing = false;
  String? _error;

  Future<void> _onCaptureCompleted(List<CapturedShot> shots) async {
    // MVP : on n'envoie que la vue de face au backend.
    final faceShot = shots.firstWhere(
      (s) => s.pose == CapturePose.face,
      orElse: () => shots.first,
    );

    setState(() {
      _analyzing = true;
      _error = null;
    });

    try {
      final result = await _api.analyzeFace(File(faceShot.path));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            result: result,
            onRetry: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_analyzing) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF1ABC9C)),
              SizedBox(height: 20),
              Text('Analyse en cours…'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Impossible de joindre le serveur d\'analyse.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Retour'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PoseCaptureScreen(
      cameras: widget.cameras,
      onCompleted: _onCaptureCompleted,
    );
  }
}
