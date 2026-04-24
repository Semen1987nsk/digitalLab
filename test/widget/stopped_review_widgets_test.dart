import 'package:digital_lab/presentation/pages/experiment/stopped_review_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('StoppedReviewPanel shows school-friendly primary actions by default', (
    tester,
  ) async {
    var fitAllTapped = 0;
    var resetTapped = 0;
    var selectionTapped = 0;

    await tester.pumpWidget(
      _wrap(
        StoppedReviewPanel(
          isSelectionMode: false,
          visibleRangeLabel: 'Сейчас видно: 0.0–30.0 с',
          onFitAll: () => fitAllTapped++,
          onResetView: () => resetTapped++,
          onToggleSelectionMode: () => selectionTapped++,
          onResetYScale: () {},
        ),
      ),
    );

    expect(find.text('Просмотр записи'), findsOneWidget);
    expect(find.text('Сейчас видно: 0.0–30.0 с'), findsOneWidget);
    expect(find.text('Весь график'), findsOneWidget);
    expect(find.text('Сбросить вид'), findsOneWidget);
    expect(find.text('Выделить участок'), findsOneWidget);
    expect(find.text('Авто Y'), findsOneWidget);
    expect(find.text('Точный режим'), findsNothing);
    expect(find.text('Левее'), findsNothing);

    await tester.tap(find.text('Весь график'));
    await tester.tap(find.text('Сбросить вид'));
    await tester.tap(find.text('Выделить участок'));
    await tester.tap(find.text('Авто Y'));
    await tester.pump();

    expect(fitAllTapped, 1);
    expect(resetTapped, 1);
    expect(selectionTapped, 1);
  });

  testWidgets('StoppedReviewPanel shows selection cancel state in one panel', (
    tester,
  ) async {
    var selectionToggled = 0;

    await tester.pumpWidget(
      _wrap(
        StoppedReviewPanel(
          isSelectionMode: true,
          visibleRangeLabel: 'Сейчас видно: 10.0–20.0 с',
          onFitAll: () {},
          onResetView: () {},
          onToggleSelectionMode: () => selectionToggled++,
          onResetYScale: () {},
        ),
      ),
    );

    expect(find.text('Отменить выделение'), findsOneWidget);
    expect(find.text('Авто Y'), findsOneWidget);
    expect(find.text('Точный режим'), findsNothing);
    expect(find.text('Проведите по графику, чтобы приблизить нужный участок.'), findsOneWidget);

    await tester.tap(find.text('Отменить выделение'));
    await tester.pump();

    expect(selectionToggled, 1);
  });

  testWidgets('selection mode shows focused guidance inside panel only', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const StoppedReviewPanel(
          isSelectionMode: true,
          visibleRangeLabel: 'Сейчас видно: 10.0–20.0 с',
          onFitAll: _noop,
          onResetView: _noop,
          onToggleSelectionMode: _noop,
          onResetYScale: _noop,
        ),
      ),
    );

    expect(
      find.text('Проведите по графику, чтобы приблизить нужный участок.'),
      findsOneWidget,
    );
    expect(find.text('Сейчас видно: 10.0–20.0 с'), findsNothing);
  });
}

void _noop() {}
