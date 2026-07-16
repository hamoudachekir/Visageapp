/// Configuration réseau partagée vers le backend FastAPI.
///
/// On utilise `127.0.0.1:8000` côté appareil : avec
/// `adb reverse tcp:8000 tcp:8000`, le téléphone (ou l'émulateur) atteint le
/// backend qui tourne sur le PC, à travers le câble USB. C'est plus fiable
/// que `10.0.2.2` (émulateur seulement) ou l'IP LAN (qui change de réseau).
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'http://127.0.0.1:8000';
}
