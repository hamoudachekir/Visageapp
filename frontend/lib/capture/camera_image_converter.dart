import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Conversion `CameraImage` -> `InputImage` pour ML Kit, partagée entre l'écran
/// de capture réel et l'aperçu AR.
///
/// Cette logique (compensation de rotation selon l'orientation device + capteur,
/// reconstruction NV21 à partir des plans yuv420 sur Android) est reprise telle
/// quelle de `pose_capture_screen.dart`, qui reste l'implémentation de référence
/// et n'est volontairement pas modifiée. On la duplique ici plutôt que d'y
/// toucher pour ne prendre aucun risque sur le flux d'analyse existant.
class CameraImageConverter {
  CameraImageConverter._();

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Calcule la rotation à appliquer à l'image pour ML Kit, en tenant compte de
  /// l'orientation du capteur, de l'orientation courante de l'appareil et du
  /// fait que la caméra frontale est miroir.
  static InputImageRotation? rotationFor(
    CameraImage image,
    CameraController controller,
  ) {
    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;

    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    var compensation = _orientations[controller.value.deviceOrientation] ?? 0;
    if (camera.lensDirection == CameraLensDirection.front) {
      compensation = (sensorOrientation + compensation) % 360;
    } else {
      compensation = (sensorOrientation - compensation + 360) % 360;
    }
    return InputImageRotationValue.fromRawValue(compensation);
  }

  /// Construit l'`InputImage` à partir d'une frame de la caméra, ou `null` si la
  /// frame n'est pas exploitable.
  static InputImage? toInputImage(
    CameraImage image,
    CameraController controller,
  ) {
    final rotation = rotationFor(image, controller);
    if (rotation == null) return null;
    if (image.planes.isEmpty) return null;

    if (Platform.isAndroid) {
      // ML Kit attend du NV21 sur Android ; on le reconstruit à partir des
      // plans yuv420 (camera_android_camerax ne sérialise pas le NV21 natif).
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
  static Uint8List _yuv420ToNv21(CameraImage image) {
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
      nv21.setRange(destOffset, destOffset + width, yPlane.bytes, srcOffset);
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
}
