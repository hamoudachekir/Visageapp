import 'package:flutter/material.dart';

/// Menu déroulant réutilisable, même habillage que [CustomTextField].
class CustomDropdownField extends StatelessWidget {
  final String label;
  final bool required;
  final String? value;
  final List<String> options;
  final String hint;
  final ValueChanged<String?>? onChanged;
  final String? Function(String?)? validator;

  const CustomDropdownField({
    super.key,
    required this.label,
    required this.options,
    this.required = false,
    this.value,
    this.hint = 'Sélectionnez une option',
    this.onChanged,
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
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(hintText: hint),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
          validator: validator,
        ),
      ],
    );
  }
}
