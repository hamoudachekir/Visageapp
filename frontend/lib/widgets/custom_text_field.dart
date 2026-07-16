import 'package:flutter/material.dart';

/// Champ de texte réutilisable, habillé par [AppTheme.light]'s
/// `inputDecorationTheme` (bordure 8px, focus teal).
class CustomTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final String? prefixText;
  final TextEditingController? controller;
  final bool required;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const CustomTextField({
    super.key,
    required this.label,
    this.hint,
    this.prefixText,
    this.controller,
    this.required = false,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
            children: required
                ? [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefixText,
          ),
        ),
      ],
    );
  }
}
