import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/skin_analysis.dart';
import '../providers/auth_provider.dart';
import '../providers/session_flow_provider.dart';
import '../screens/analyzing_screen.dart';
import '../screens/skin_result_screen.dart';
import '../services/skin_api.dart';
import 'capture_pose.dart';
import 'photo_validation_screen.dart';
import 'pose_capture_screen.dart';

/// Orchestre le flux : capture des 4 vues -> validation -> analyse peau -> résultat.
class CaptureFlow extends ConsumerWidget {
  final List<CameraDescription> cameras;

  const CaptureFlow({super.key, required this.cameras});

  void _onCaptureCompleted(
      BuildContext context, WidgetRef ref, List<CapturedShot> shots) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoValidationScreen(
          cameras: cameras,
          shots: shots,
          onConfirmed: (confirmed) => _startAnalysis(context, ref, confirmed),
        ),
      ),
    );
  }

  void _startAnalysis(
      BuildContext context, WidgetRef ref, List<CapturedShot> shots) {
    File? fileFor(CapturePose pose) {
      for (final shot in shots) {
        if (shot.pose == pose) return File(shot.path);
      }
      return null;
    }

    // Correspondance poses locales -> champs du backend :
    // face -> front, profils -> left/right, gros plan du front -> closeup.
    final front = fileFor(CapturePose.face);
    final left = fileFor(CapturePose.profilGauche);
    final right = fileFor(CapturePose.profilDroit);
    final closeup = fileFor(CapturePose.front);
    if (front == null || left == null || right == null || closeup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Il manque une photo — refaites la capture.')),
      );
      return;
    }

    final api = SkinApi(token: ref.read(authProvider).session?.token);
    final clientId = ref.read(sessionFlowProvider).client?.id;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalyzingScreen<SkinAnalysisResult>(
          analyze: () => api.analyze(
            front: front,
            left: left,
            right: right,
            closeup: closeup,
            clientId: clientId,
          ),
          onResult: (result) async {
            final catalog = await api.fetchBrands();
            if (!context.mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => SkinResultScreen(
                  result: result,
                  frontPhoto: front,
                  brandCatalog: catalog,
                  onRetry: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                ),
              ),
            );
          },
          onRetry: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La capture guidée s'appuie sur ML Kit, non disponible en navigateur :
    // sur le web on affiche un message plutôt que d'initialiser la caméra.
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Capture photo')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smartphone, size: 56),
                SizedBox(height: 16),
                Text(
                  "La capture photo et l'analyse se font sur l'application "
                  'mobile. Le profil et le diagnostic sont déjà enregistrés.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return PoseCaptureScreen(
      cameras: cameras,
      onCompleted: (shots) => _onCaptureCompleted(context, ref, shots),
    );
  }
}
