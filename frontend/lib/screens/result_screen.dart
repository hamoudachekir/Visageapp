import 'package:flutter/material.dart';

import '../services/analysis_api.dart';

/// Affiche le résultat de l'analyse : sexe + âge estimé.
class ResultScreen extends StatelessWidget {
  final AnalysisResult result;
  final VoidCallback onRetry;

  const ResultScreen({
    super.key,
    required this.result,
    required this.onRetry,
  });

  static const _teal = Color(0xFF1ABC9C);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Résultat'),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: result.ok ? _buildSuccess(context) : _buildFailure(context),
        ),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final sexe = result.sexe ?? '—';
    final age = result.ageEstime?.toString() ?? '—';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: _teal, size: 72),
        const SizedBox(height: 24),
        _InfoCard(
          icon: sexe == 'Homme' ? Icons.male : Icons.female,
          label: 'Sexe',
          value: sexe,
        ),
        const SizedBox(height: 16),
        _InfoCard(
          icon: Icons.cake,
          label: 'Âge estimé',
          value: '$age ans',
        ),
        if (result.confiance != null) ...[
          const SizedBox(height: 16),
          Text(
            'Confiance de détection : ${(result.confiance! * 100).toStringAsFixed(0)} %',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
        const SizedBox(height: 40),
        _retryButton(),
      ],
    );
  }

  Widget _buildFailure(BuildContext context) {
    final raison = result.raison == 'aucun_visage_detecte'
        ? 'Aucun visage n\'a été détecté sur la photo de face.'
        : 'L\'analyse a échoué (${result.raison ?? "raison inconnue"}).';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 72),
        const SizedBox(height: 24),
        Text(
          raison,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 40),
        _retryButton(),
      ],
    );
  }

  Widget _retryButton() {
    return ElevatedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Refaire la capture'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 36, color: const Color(0xFF1ABC9C)),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
