import 'package:analyse_faciale/screens/skin_result/severity_style.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:analyse_faciale/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('severityColor maps each severity', () {
    expect(severityColor(Severity.faible), AppColors.positive);
    expect(severityColor(Severity.moderee), const Color(0xFFE8973A));
    expect(severityColor(Severity.marquee), AppColors.negative);
  });

  test('severityBg maps each severity', () {
    expect(severityBg(Severity.faible), AppColors.positiveLight);
    expect(severityBg(Severity.moderee), const Color(0xFFFFF3E0));
    expect(severityBg(Severity.marquee), AppColors.negativeLight);
  });
}
