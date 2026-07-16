import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

enum SessionType { nouveauClient, clientExistant }

Future<SessionType?> showSessionTypeDialog(BuildContext context) {
  return showDialog<SessionType>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Type de session',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0B1C30),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Comment souhaitez-vous démarrer ?',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF5A6B6D),
              ),
            ),
            const SizedBox(height: 22),
            _SessionChoiceCard(
              icon: Icons.person_add_alt_1,
              title: 'Nouveau client',
              subtitle: 'Créer un profil et démarrer un diagnostic',
              primary: true,
              onTap: () => Navigator.of(context).pop(SessionType.nouveauClient),
            ),
            const SizedBox(height: 12),
            _SessionChoiceCard(
              icon: Icons.search,
              title: 'Client existant',
              subtitle: 'Retrouver une fiche par téléphone',
              primary: false,
              onTap: () => Navigator.of(context).pop(SessionType.clientExistant),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SessionChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  const _SessionChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconTile = primary
        ? Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF12A6AE), Color(0xFF006168)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x330C7C84),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          )
        : Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.search, color: AppColors.primary, size: 26),
          );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: primary ? const Color(0xFFBFE6E8) : const Color(0xFFE4EDEE),
              width: primary ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              iconTile,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0B1C30),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.3,
                        color: const Color(0xFF5A6B6D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Color(0xFF9AAAAB)),
            ],
          ),
        ),
      ),
    );
  }
}
