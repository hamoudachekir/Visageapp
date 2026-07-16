import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../theme/app_colors.dart';
import 'ar_face_overlay.dart';
import 'capture_pose.dart';
import 'face_pose_validator.dart';
import 'guidance_overlay.dart';
import 'pose_guide.dart';

/// Photo capturée associée à sa vue.
class CapturedShot {
  final CapturePose pose;
  final String path;
  CapturedShot(this.pose, this.path);
}

/// Écran de capture guidée des 4 vues nécessaires à l'analyse.
///
/// En mode normal, [onCompleted] est appelé une fois les 4 vues capturées.
/// En mode reprise (depuis l'écran de validation), [retakePose] et
/// [existingShots] permettent de ne reprendre qu'une seule vue : la capture
/// de cette unique vue déclenche directement [onCompleted] avec la liste
/// fusionnée, sans repasser par les autres étapes.
class PoseCaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final void Function(List<CapturedShot> shots) onCompleted;
  final CapturePose? retakePose;
  final List<CapturedShot> existingShots;

  const PoseCaptureScreen({
    super.key,
    required this.cameras,
    required this.onCompleted,
    this.retakePose,
    this.existingShots = const [],
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

  // Dernier visage détecté + métadonnées image, pour l'overlay AR.
  Face? _face;
  Size? _imageSize;
  InputImageRotation? _rotation;

  final List<CapturedShot> _shots = [];

  // Stabilisation : ~0,4 s avant de passer au vert (évite le clignotement).
  static const int _requiredStableFrames = 6;

  final _orientations = const {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  PoseConfig get _cfg => kCaptureFlow[_stepIndex];
  bool get _isSingleRetake => widget.retakePose != null;

  @override
  void initState() {
    super.initState();
    if (widget.retakePose != null) {
      _stepIndex = kCaptureFlow.indexWhere((c) => c.pose == widget.retakePose);
      _shots.addAll(
        widget.existingShots.where((s) => s.pose != widget.retakePose),
      );
    }
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
      // Note : on demande du yuv420 (et non nv21) car camera_android_camerax
      // renvoie un NV21ImageProxy interne non sérialisable par le plugin
      // quand on force directement le format nv21, ce qui fait planter l'appli.
      // On reconvertit donc nous-mêmes les plans yuv420 en NV21 plus bas.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
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
          _face = faces.isEmpty ? null : faces.first;
          _imageSize = size;
          _rotation = inputImage.metadata?.rotation;
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

    if (image.planes.isEmpty) return null;

    if (Platform.isAndroid) {
      // ML Kit attend du NV21 sur Android ; on le reconstruit à partir
      // des plans yuv420 (voir commentaire dans _initCamera).
      final bytes = _yuv420ToNv21(image);
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
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

  /// Convertit les plans Y/U/V (yuv420) en un buffer NV21 (Y puis VU entrelacés).
  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = width * height;
    final uvSize = width * height ~/ 2;
    final nv21 = Uint8List(ySize + uvSize);

    var destOffset = 0;
    for (var row = 0; row < height; row++) {
      final srcOffset = row * yPlane.bytesPerRow;
      nv21.setRange(
        destOffset,
        destOffset + width,
        yPlane.bytes,
        srcOffset,
      );
      destOffset += width;
    }

    final uRowStride = uPlane.bytesPerRow;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vRowStride = vPlane.bytesPerRow;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    var uvIndex = ySize;
    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        final uIndex = row * uRowStride + col * uPixelStride;
        final vIndex = row * vRowStride + col * vPixelStride;
        nv21[uvIndex++] = vPlane.bytes[vIndex];
        nv21[uvIndex++] = uPlane.bytes[uIndex];
      }
    }

    return nv21;
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

      if (_isSingleRetake) {
        // Mode reprise depuis l'écran de validation : une seule vue à
        // capturer, on renvoie directement la liste fusionnée.
        widget.onCompleted(_shots);
        return;
      }

      // Sélection libre : on enchaîne automatiquement sur la prochaine vue NON
      // encore capturée (confort), mais on ne quitte PAS l'écran tant que tout
      // n'est pas pris. L'utilisateur peut retoucher n'importe quelle vue via
      // les miniatures, puis valider avec « Continuer ».
      final next = _firstUncapturedIndex();
      if (next != null) {
        setState(() {
          _stepIndex = next;
          _resetStepState();
        });
        await _restartCameraForStep();
        await _ensureStreaming();
      } else {
        // Toutes les vues sont prises : on reste sur place (le bouton
        // « Continuer » apparaît) et on relance le flux pour permettre une
        // reprise éventuelle de la vue courante.
        setState(_resetStepState);
        await _ensureStreaming();
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Index de la première vue non encore capturée, ou `null` si tout est pris.
  int? _firstUncapturedIndex() {
    for (var i = 0; i < kCaptureFlow.length; i++) {
      if (!_isCaptured(kCaptureFlow[i].pose)) return i;
    }
    return null;
  }

  bool _isCaptured(CapturePose pose) => _shots.any((s) => s.pose == pose);

  bool get _allCaptured => _shots.length == kCaptureFlow.length;

  void _resetStepState() {
    _conforme = false;
    _stableFrames = 0;
    _hint = 'Initialisation…';
  }

  /// Sélectionne une vue à (re)capturer depuis les miniatures. Ne supprime pas
  /// la photo existante : elle ne sera remplacée qu'à la prochaine capture.
  Future<void> _selectPose(CapturePose pose) async {
    if (_capturing) return;
    final idx = kCaptureFlow.indexWhere((c) => c.pose == pose);
    if (idx < 0 || idx == _stepIndex) return;
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

  static const _frameTeal = Color(0xFF7BD4DD);
  static const _green = Color(0xFF2BC974);

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            _CoverPreview(controller: controller)
          else
            const Center(child: CircularProgressIndicator(color: _frameTeal)),
          if (ready) const _EdgeVignette(),
          if (ready) GuidanceOverlay(conforme: _conforme),
          if (ready)
            ArFaceOverlay(
              face: _face,
              imageSize: _imageSize,
              rotation: _rotation,
              mirror: controller.description.lensDirection ==
                  CameraLensDirection.front,
            ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const SizedBox(height: 10),
                _buildProgress(),
                const Spacer(),
                _buildStatusHint(),
                const SizedBox(height: 18),
                _buildFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.black.withAlpha(110),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.close, color: Colors.white, size: 22),
              ),
            ),
          ),
          const Spacer(),
          PoseGuide(pose: _cfg.pose),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return Column(
      children: [
        Text(
          _cfg.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${_shots.length}/${kCaptureFlow.length} vues capturées · touchez une vignette',
          style: TextStyle(
            color: Colors.white.withAlpha(190),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < kCaptureFlow.length; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 6,
                width: 40,
                decoration: BoxDecoration(
                  // Vert = capturée ; teal = vue courante ; sinon discret.
                  color: _isCaptured(kCaptureFlow[i].pose)
                      ? _green
                      : (i == _stepIndex
                          ? _frameTeal
                          : Colors.white.withAlpha(50)),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusHint() {
    final ok = _conforme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(130),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: ok ? _green : _frameTeal, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.center_focus_weak,
              color: ok ? _green : _frameTeal,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              ok ? 'Visage détecté' : _hint,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87, Colors.black],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildThumbnails(),
          const SizedBox(height: 18),
          _buildCaptureButton(),
          const SizedBox(height: 12),
          if (_allCaptured)
            _buildContinueButton()
          else
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, color: Colors.white54, size: 15),
                SizedBox(width: 6),
                Text(
                  'Placez-vous dans un endroit bien éclairé',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(120),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => widget.onCompleted(_shots),
            child: const SizedBox(
              height: 52,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Continuer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnails() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: kCaptureFlow.map((cfg) {
        final matches = _shots.where((s) => s.pose == cfg.pose);
        final shot = matches.isEmpty ? null : matches.first;
        final isCurrent = cfg.pose == _cfg.pose;
        final captured = shot != null;
        // Vue courante = teal (épais) ; capturée = vert ; sinon discret.
        final borderColor =
            isCurrent ? _frameTeal : (captured ? _green : Colors.white38);
        final borderWidth = isCurrent ? 3.0 : (captured ? 2.0 : 1.0);
        final labelColor =
            isCurrent ? _frameTeal : (captured ? _green : Colors.white60);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GestureDetector(
            onTap: () => _selectPose(cfg.pose),
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withAlpha(15),
                    border: Border.all(color: borderColor, width: borderWidth),
                    boxShadow: isCurrent
                        ? [BoxShadow(color: _frameTeal.withAlpha(90), blurRadius: 12)]
                        : null,
                  ),
                  child: captured
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(shot.path), fit: BoxFit.cover),
                            Positioned(
                              top: 3,
                              right: 3,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _green,
                                ),
                                child: const Icon(Icons.check,
                                    color: Colors.white, size: 11),
                              ),
                            ),
                          ],
                        )
                      : Icon(cfg.icon,
                          color: isCurrent ? _frameTeal : Colors.white38,
                          size: 24),
                ),
                const SizedBox(height: 6),
                Text(
                  shortPoseLabel(cfg.pose),
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCaptureButton() {
    final active = _conforme && !_capturing;
    return GestureDetector(
      onTap: active ? _capture : null,
      child: Container(
        width: 84,
        height: 84,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _frameTeal.withAlpha(active ? 255 : 90),
            width: 4,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.primaryDark : Colors.white24,
            boxShadow: active
                ? [BoxShadow(color: AppColors.primary.withAlpha(130), blurRadius: 24)]
                : null,
          ),
          child: _capturing
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3),
                )
              : const Icon(Icons.photo_camera, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

/// Aperçu caméra plein cadre (recadré en cover).
class _CoverPreview extends StatelessWidget {
  final CameraController controller;

  const _CoverPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.width * controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

/// Vignettage doux des bords (assombrit le pourtour, focalise sur le visage).
class _EdgeVignette extends StatelessWidget {
  const _EdgeVignette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.0,
            colors: [Colors.transparent, Colors.black.withAlpha(150)],
            stops: const [0.55, 1.0],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
