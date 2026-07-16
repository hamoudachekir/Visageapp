import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tolérant aux plateformes sans caméra (web / desktop) : l'auth et la
  // navigation fonctionnent quand même, seule la capture serait indisponible.
  var cameras = <CameraDescription>[];
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Caméras indisponibles : $e');
  }
  runApp(LuminaApp(cameras: cameras));
}

class LuminaApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const LuminaApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp.router(
        title: 'Lumina',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: buildAppRouter(cameras),
      ),
    );
  }
}
