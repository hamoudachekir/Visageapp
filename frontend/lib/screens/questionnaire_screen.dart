import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../capture/capture_flow.dart';
import '../models/questionnaire_answers.dart';
import '../providers/session_flow_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/lumina_ui.dart';
import 'diagnostic_saved_screen.dart';

class _Question {
  final String section;
  final IconData icon;
  final String prompt;
  final List<String> options;

  const _Question({
    required this.section,
    required this.icon,
    required this.prompt,
    required this.options,
  });
}

const _questions = [
  _Question(
    section: 'Type de peau',
    icon: Icons.water_drop_outlined,
    prompt: 'Comment décririez-vous le type de peau du client ?',
    options: ['Sèche', 'Grasse', 'Mixte', 'Normale'],
  ),
  _Question(
    section: 'Tendance acnéique',
    icon: Icons.healing_outlined,
    prompt: 'Le client présente-t-il une tendance acnéique ?',
    options: ['Aucune', 'Légère', 'Modérée', 'Sévère'],
  ),
  _Question(
    section: 'Sensibilité cutanée',
    icon: Icons.spa_outlined,
    prompt: 'Comment qualifieriez-vous la sensibilité de la peau ?',
    options: ['Faible', 'Moyenne', 'Élevée'],
  ),
];

/// Questionnaire de peau en 3 questions, dernière étape avant la capture photo.
class QuestionnaireScreen extends ConsumerStatefulWidget {
  final List<CameraDescription> cameras;

  const QuestionnaireScreen({super.key, required this.cameras});

  @override
  ConsumerState<QuestionnaireScreen> createState() =>
      _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends ConsumerState<QuestionnaireScreen> {
  int _step = 0;
  bool _saving = false;
  final List<String?> _answers = List.filled(_questions.length, null);

  void _selectOption(String option) {
    setState(() => _answers[_step] = option);
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step -= 1);
  }

  void _exitFlow() {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _next() {
    if (_answers[_step] == null || _saving) return;
    if (_step < _questions.length - 1) {
      setState(() => _step += 1);
      return;
    }
    _finish();
  }

  /// Dernière étape : enregistre le client (s'il est nouveau) puis son
  /// diagnostic en base, avant la capture (mobile) ou la confirmation (web).
  Future<void> _finish() async {
    final answers = QuestionnaireAnswers(
      typePeau: _answers[0]!,
      tendanceAcneique: _answers[1]!,
      sensibiliteCutanee: _answers[2]!,
    );
    final flow = ref.read(sessionFlowProvider.notifier);
    flow.setAnswers(answers);

    final initial = ref.read(sessionFlowProvider).client;
    if (initial == null) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(clientRepositoryProvider);
      var client = initial;
      if (!client.isPersisted) {
        client = await repo.save(client);
        flow.setClient(client);
      }
      await repo.saveDiagnostic(client.id!, answers);
      if (!mounted) return;

      if (kIsWeb) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DiagnosticSavedScreen(client: client),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CaptureFlow(cameras: widget.cameras),
          ),
        );
      }
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = _questions[_step];
    final isLast = _step == _questions.length - 1;
    final canContinue = _answers[_step] != null;

    return Scaffold(
      backgroundColor: LuminaUi.bg,
      body: Column(
        children: [
          LuminaHeader(
            title: 'Questionnaire',
            subtitle: 'Question ${_step + 1} sur ${_questions.length}',
            onBack: _goBack,
            trailing: _CircleClose(onTap: _exitFlow),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                for (var i = 0; i < _questions.length; i++)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                          right: i < _questions.length - 1 ? 6 : 0),
                      height: 6,
                      decoration: BoxDecoration(
                        color: i <= _step
                            ? AppColors.primary
                            : const Color(0xFFD7E3E4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: LuminaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(question.icon,
                              color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          question.section,
                          style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      question.prompt,
                      style: GoogleFonts.fraunces(
                        fontSize: 21,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: LuminaUi.navy,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...question.options.map(
                      (option) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _OptionTile(
                          label: option,
                          selected: _answers[_step] == option,
                          onTap: () => _selectOption(option),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _BottomBar(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _goBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: Color(0xFFBFE6E8)),
                    minimumSize: const Size(0, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: GoogleFonts.inter(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Précédent'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LuminaGradientButton(
                  label: isLast ? 'Enregistrer' : 'Suivant',
                  icon: isLast ? Icons.check : Icons.arrow_forward,
                  loading: _saving,
                  onPressed: canContinue ? _next : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : LuminaUi.fieldFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : const Color(0xFFAAB7B8),
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? AppColors.primary : LuminaUi.navy,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleClose extends StatelessWidget {
  final VoidCallback onTap;

  const _CircleClose({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: LuminaUi.hairline)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(9),
          child: Icon(Icons.close, size: 20, color: LuminaUi.navy),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final List<Widget> children;

  const _BottomBar({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: LuminaUi.bg,
        border: Border(top: BorderSide(color: LuminaUi.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: children),
        ),
      ),
    );
  }
}
