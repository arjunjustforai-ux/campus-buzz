import 'package:campusbuzz/core/theme/app_colors.dart';
import 'package:campusbuzz/features/events/data/event_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recommendation reason codes have copy', () {
    for (final c in ['because_of_tribe', 'similar_to_attended', 'friends_attending', 'popular_on_campus', 'happening_soon']) {
      expect(reasonCopy(c, const {}), isNot(c));
    }
  });

  test('band colours are distinct and accessible against dark', () {
    final colors = {CbColors.bandColor('green'), CbColors.bandColor('yellow'), CbColors.bandColor('red'), CbColors.bandColor('no_data')};
    expect(colors.length, 4);
    for (final c in colors) {
      final l = c.computeLuminance();
      final contrast = (l + 0.05) / (CbColors.surface1.computeLuminance() + 0.05);
      expect(contrast, greaterThan(3), reason: 'status colour ${c.toARGB32().toRadixString(16)} must stand out on dark surfaces');
    }
    expect((CbColors.textPrimary.computeLuminance() + 0.05) / (CbColors.surface0.computeLuminance() + 0.05), greaterThan(7));
    expect((CbColors.limeText.computeLuminance() + 0.05) / (CbColors.surface0.computeLuminance() + 0.05), greaterThan(4.5));
  });
}
