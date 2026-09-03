import 'package:campusbuzz/core/models/models.dart';
import 'package:campusbuzz/core/theme/app_theme.dart';
import 'package:campusbuzz/core/widgets/cb_widgets.dart';
import 'package:campusbuzz/core/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget wrap(Widget child) => MaterialApp(theme: CbTheme.dark(), home: Scaffold(body: child));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('band pill never relies on colour alone', (t) async {
    await t.pumpWidget(wrap(Column(children: [bandPill('green'), bandPill('yellow'), bandPill('red'), bandPill('no_data')])));
    expect(find.text('On track'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    expect(find.text('Behind'), findsOneWidget);
    expect(find.text('No data'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
  });

  testWidgets('CbStat renders label, value, hint', (t) async {
    await t.pumpWidget(wrap(const CbStat(label: 'WAP', value: '42', hint: '30% of registered', band: 'green')));
    expect(find.text('WAP'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('30% of registered'), findsOneWidget);
  });

  testWidgets('empty and error states show retry actions', (t) async {
    var retried = 0;
    await t.pumpWidget(wrap(Column(children: [Expanded(child: CbEmpty(title: 'Nothing', action: () => retried++, actionLabel: 'Reload')), Expanded(child: CbErrorView(error: Exception('boom'), onRetry: () => retried++))])));
    expect(find.text('Nothing'), findsOneWidget);
    expect(find.text('Something broke'), findsOneWidget);
    await t.tap(find.text('Reload'));
    await t.tap(find.text('Try again'));
    expect(retried, 2);
  });

  testWidgets('CbChip is semantically a button with selected state', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(CbChip(label: 'Coders', selected: true, onTap: () => tapped = true)));
    await t.tap(find.text('Coders'));
    expect(tapped, isTrue);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true && w.properties.button == true && w.properties.label == 'Coders'), findsOneWidget);
  });

  testWidgets('coin badge shows sign and amount', (t) async {
    await t.pumpWidget(wrap(const Row(children: [CbCoinBadge(amount: 20), CbCoinBadge(amount: 100, prefix: '')])));
    expect(find.text('+20'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('touch targets meet minimum size', (t) async {
    await t.pumpWidget(wrap(FilledButton(onPressed: () {}, child: const Text('RSVP'))));
    final size = t.getSize(find.byType(FilledButton));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  test('Role labels are human', () {
    expect(Role.campusAdmin.label, 'Campus Ops');
    expect(Role.vendor.label, 'Redemption partner');
  });
}
