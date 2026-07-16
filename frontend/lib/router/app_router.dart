import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';

import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/splash_screen.dart';

/// Construit la configuration GoRouter de l'application. [cameras] doit
/// être résolu (via `availableCameras()`) avant l'appel, puisque l'écran
/// d'accueil en a besoin pour lancer la capture.
GoRouter buildAppRouter(List<CameraDescription> cameras) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => SplashScreen(
          onResolved: (isLoggedIn) =>
              context.go(isLoggedIn ? '/home' : '/login'),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          onLoggedIn: () => context.go('/home'),
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => HomeScreen(cameras: cameras),
      ),
    ],
  );
}
