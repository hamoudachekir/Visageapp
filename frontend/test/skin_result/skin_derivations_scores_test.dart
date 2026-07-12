import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter_test/flutter_test.dart';

SkinCondition cond(String code, int score, {String? label}) => SkinCondition(
      code: code,
      labelFr: label ?? code,
      score: score,
      severity: 'x',
    );

void main() {
  test('healthScore inverts raw score', () {
    expect(healthScore(cond('redness', 28)), 72);
    expect(healthScore(cond('acne', 0)), 100);
  });

  test('severityBand thresholds', () {
    expect(severityBand(29), Severity.faible);
    expect(severityBand(30), Severity.moderee);
    expect(severityBand(59), Severity.moderee);
    expect(severityBand(60), Severity.marquee);
  });

  test('severityLabel is French', () {
    expect(severityLabel(Severity.faible), 'faible');
    expect(severityLabel(Severity.moderee), 'modérée');
    expect(severityLabel(Severity.marquee), 'marquée');
  });

  test('globalScore is mean of health, rounded; null when empty', () {
    expect(globalScore([]), isNull);
    // health 80 + 60 => mean 70
    expect(globalScore([cond('a', 20), cond('b', 40)]), 70);
  });

  test('globalLabel bands', () {
    expect(globalLabel(80), 'Excellent');
    expect(globalLabel(79), 'Bon');
    expect(globalLabel(65), 'Bon');
    expect(globalLabel(64), 'Correct');
    expect(globalLabel(50), 'Correct');
    expect(globalLabel(49), 'À améliorer');
  });

  test('flaggedCodes are score >= 30', () {
    expect(flaggedCodes([cond('a', 30), cond('b', 10), cond('c', 55)]),
        {'a', 'c'});
  });

  test('priorityConditions filters >=30 and sorts worst-first', () {
    final out = priorityConditions([cond('a', 30), cond('b', 70), cond('c', 5)]);
    expect(out.map((c) => c.code).toList(), ['b', 'a']);
  });

  test('reportConditions sorts by health descending (raw ascending)', () {
    final out = reportConditions([cond('a', 40), cond('b', 10), cond('c', 90)]);
    expect(out.map((c) => c.code).toList(), ['b', 'a', 'c']);
  });

  test('deriveObservation splits forts (<30, top4 healthiest) and vigilance', () {
    final obs = deriveObservation([
      cond('r', 40, label: 'Rougeurs'),
      cond('s', 35, label: 'Sébum'),
      cond('w', 5, label: 'Rides'),
      cond('t', 8, label: 'Taches'),
    ]);
    expect(obs.forts, ['Rides', 'Taches']);
    expect(obs.vigilance, ['Rougeurs', 'Sébum']);
  });
}
