import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'capture_pose.dart';
import 'face_pose_validator.dart';
import 'guidance_overlay.dart';

/// Photo capturée associée à sa vue.
class CapturedShot {
  final CapturePose pose;
  final String path;
  CapturedShot(this.pose, this.path);
}

/// Écran de capture guidée des 4 vues nécessaires à l'analyse.
class PoseCaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final void Function(List<CapturedShot> shots) onCompleted;

  const PoseCaptureScreen({
    super.key,
    required this.cameras,
    required this.onCompleted,
  });

  @override
  State<PoseCaptureScreen> createState() => _PoseCaptureScreenState();
}

class _PoseCaptureScreenState extends State<PoseCaptureScreen> {
  CameraController? _controller;
  late FaceDetector _faceDetector;

  int _stepIndex = 0;
  bool _isBusy = false; // anti-saturation du flux d'analyse
  bool _conforme = false;
  String _hint = 'Initialisation…';
  int _stableFrames = 0; // nb de frames consécutives conformes
  bool _capturing = false;

  final List<CapturedShot> _shots = [];

  // Stabilisation : ~0,4 s avant de passer au vert (évite le clignotement).
  static const int _requiredStableFrames = 6;

  static const _teal = Color(0xFF1ABC9C);
  static const _vert = Color(0xFF2ECC71);
  static const _rouge = Color(0xFFE74C3C);

  final _orientations = const {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  PoseConfig get _cfg => kCaptureFlow[_stepIndex];
  bool get _allCaptured => _shots.length == kCaptureFlow.length;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: true,
      ),
    );
    _initCamera();
  }

  /// Caméra frontale pour les vues du visage, arrière pour le dessus de la tête.
  CameraDescription _selectCamera() {
    final wantFront = _cfg.requiresFace;
    return widget.cameras.firstWhere(
      (c) => wantFront
          ? c.lensDirection == CameraLensDirection.front
          : c.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );
  }

  Future<void> _initCamera() async {
    final camera = _selectCamera();
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    _controller = controller;
    await controller.initialize();
    if (!mounted) return;
    await controller.startImageStream(_processFrame);
    setState(() {});
  }

  /// Réinitialise la caméra seulement si la vue suivante change d'objectif.
  Future<void> _restartCameraForStep() async {
    final desired = _selectCamera();
    if (_controller != null &&
        _controller!.description.lensDirection == desired.lensDirection) {
      return; // même caméra : on relancera juste le flux
    }
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
    await _initCamera();
  }

  Future<void> _ensureStreaming() async {
    final c = _controller;
    if (c != null && c.value.isInitialized && !c.value.isStreamingImages) {
      await c.startImageStream(_processFrame);
    }
  }

  void _processFrame(CameraImage image) async {
    if (_isBusy || _capturing) return;
    _isBusy = true;
    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      final size = inputImage.metadata?.size ??
          Size(image.width.toDouble(), image.height.toDouble());
      final eval = FacePoseValidator.evaluate(_cfg, faces, size);

      _stableFrames = eval.conforme ? _stableFrames + 1 : 0;
      final nowConforme = _stableFrames >= _requiredStableFrames;

      if (mounted) {
        setState(() {
          _conforme = nowConforme;
          _hint = eval.hint;
        });
      }
    } catch (_) {
      // on ignore les erreurs ponctuelles de frame
    } finally {
      _isBusy = false;
    }
  }

  /// Conversion CameraImage -> InputImage (gestion rotation selon device).
  InputImage? _toInputImage(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;
    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else {
      var compensation = _orientations[controller.value.deviceOrientation] ?? 0;
      if (camera.lensDirection == CameraLensDirection.front) {
        compensation = (sensorOrientation + compensation) % 360;
      } else {
        compensation = (sensorOrientation - compensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(compensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || image.planes.isEmpty) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || !_conforme) return;
    setState(() => _capturing = true);
    try {
      await controller.stopImageStream();
      final file = await controller.takePicture();
      _shots.removeWhere((s) => s.pose == _cfg.pose); // évite les doublons
      _shots.add(CapturedShot(_cfg.pose, file.path));

      if (_stepIndex < kCaptureFlow.length - 1) {
        setState(() {
          _stepIndex++;
          _resetStepState();
        });
        await _restartCameraForStep();
        await _ensureStreaming();
      }
      // Si c'était la dernière vue, on laisse le flux arrêté (validation finale).
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _resetStepState() {
    _conforme = false;
    _stableFrames = 0;
    _hint = 'Initialisation…';
  }

  /// Recommencer la vue en cours.
  Future<void> _retakeCurrent() async {
    _shots.removeWhere((s) => s.pose == _cfg.pose);
    setState(_resetStepState);
    await _ensureStreaming();
  }

  /// Reprendre une vue déjà capturée (depuis une miniature).
  Future<void> _retakeShot(CapturedShot shot) async {
    final idx = kCaptureFlow.indexWhere((c) => c.pose == shot.pose);
    _shots.removeWhere((s) => s.pose == shot.pose);
    setState(() {
      _stepIndex = idx;
      _resetStepState();
    });
    await _restartCameraForStep();
    await _ensureStreaming();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildProgress(),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (ready)
                    CameraPreview(controller)
                  else
                    const Center(child: CircularProgressIndicator()),
                  if (ready)
                    GuidanceOverlay(
                      conforme: _conforme,
                      isTopView: !_cfg.requiresFace,
                    ),
                  _buildInstruction(),
                  _buildHint(),
                ],
              ),
            ),
            _buildThumbnails(),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Étape ${_stepIndex + 1}/${kCaptureFlow.length} — ${_cfg.label}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          Row(
            children: List.generate(kCaptureFlow.length, (i) {
              final done = _shots.any((s) => s.pose == kCaptureFlow[i].pose);
              final current = i == _stepIndex;
              return Container(
                width: 26,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: done
                      ? _vert
                      : current
                          ? _teal
                          : Colors.white24,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildInstruction() {
    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Icon(_cfg.icon, color: Colors.white, size: 40),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _cfg.instruction,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint() {
    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _conforme ? _vert : _rouge,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _conforme ? '✓ Position correcte' : _hint,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnails() {
    if (_shots.isEmpty) return const SizedBox(height: 8);
    final ordered = [...kCaptureFlow]
        .where((c) => _shots.any((s) => s.pose == c.pose))
        .map((c) => _shots.firstWhere((s) => s.pose == c.pose))
        .toList();
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: ordered.map((s) {
          return GestureDetector(
            onTap: () => _retakeShot(s),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _vert, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(File(s.path), fit: BoxFit.cover),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Recommencer la vue courante
          IconButton(
            onPressed: _capturing ? null : _retakeCurrent,
            icon: const Icon(Icons.refresh, color: Colors.white, size: 28),
            tooltip: 'Recommencer cette vue',
          ),
          // Bouton de capture — actif uniquement si la position est conforme
          GestureDetector(
            onTap: (_conforme && !_capturing) ? _capture : null,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _conforme ? _vert : Colors.white24,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: _capturing
                  ? const Padding(
                      padding: EdgeInsets.all(22),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 3),
                    )
                  : const Icon(Icons.camera_alt, color: Colors.white, size: 30),
            ),
          ),
          // Validation finale — active quand les 4 vues sont capturées
          IconButton(
            onPressed:
                _allCaptured ? () => widget.onCompleted(_shots) : null,
            icon: Icon(
              Icons.check_circle,
              color: _allCaptured ? _vert : Colors.white24,
              size: 34,
            ),
            tooltip: 'Valider',
          ),
        ],
      ),
    );
  }
}
