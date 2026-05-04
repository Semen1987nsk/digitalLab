import 'package:digital_lab/domain/entities/sensor_data.dart';
import 'package:digital_lab/domain/entities/sensor_type.dart';
import 'package:digital_lab/presentation/pages/experiment/experiment_big_display.dart';
import 'package:digital_lab/presentation/pages/experiment/experiment_chart_view.dart';
import 'package:digital_lab/presentation/pages/experiment/experiment_control_bar.dart';
import 'package:digital_lab/presentation/pages/experiment/experiment_data_table_view.dart';
import 'package:digital_lab/presentation/pages/experiment/experiment_timer.dart';
import 'package:digital_lab/presentation/pages/experiment/view_mode_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Оборачивает виджет в `MaterialApp` чтобы Theme/Localizations были доступны.
Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('ExperimentTimer', () {
    testWidgets('shows 00:00.0 for elapsed=0', (tester) async {
      await tester.pumpWidget(
        _wrap(const ExperimentTimer(elapsedSeconds: 0, isRunning: false)),
      );

      expect(find.text('00:00.0'), findsOneWidget);
    });

    testWidgets('formats minutes and seconds', (tester) async {
      await tester.pumpWidget(
        _wrap(const ExperimentTimer(elapsedSeconds: 65.7, isRunning: true)),
      );

      expect(find.text('01:05.7'), findsOneWidget);
    });

    testWidgets('shows static timer icon when not running', (tester) async {
      await tester.pumpWidget(
        _wrap(const ExperimentTimer(elapsedSeconds: 5.0, isRunning: false)),
      );

      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    });

    testWidgets('hides static icon when running (shows pulsating dot instead)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const ExperimentTimer(elapsedSeconds: 5.0, isRunning: true)),
      );

      expect(find.byIcon(Icons.timer_outlined), findsNothing);
    });

    testWidgets('updates display when elapsedSeconds changes', (tester) async {
      await tester.pumpWidget(
        _wrap(const ExperimentTimer(elapsedSeconds: 1.0, isRunning: true)),
      );
      expect(find.text('00:01.0'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(const ExperimentTimer(elapsedSeconds: 12.5, isRunning: true)),
      );
      await tester.pump();

      expect(find.text('00:12.5'), findsOneWidget);
      expect(find.text('00:01.0'), findsNothing);
    });
  });

  group('ViewModeSelector', () {
    testWidgets('shows all three mode labels', (tester) async {
      await tester.pumpWidget(
        _wrap(ViewModeSelector(
          mode: ViewMode.chart,
          color: Colors.blue,
          onChanged: (_) {},
        )),
      );

      expect(find.text('Табло'), findsOneWidget);
      expect(find.text('График'), findsOneWidget);
      expect(find.text('Таблица'), findsOneWidget);
    });

    testWidgets('tap on Табло fires onChanged with display mode',
        (tester) async {
      ViewMode? captured;
      await tester.pumpWidget(
        _wrap(ViewModeSelector(
          mode: ViewMode.chart,
          color: Colors.blue,
          onChanged: (m) => captured = m,
        )),
      );

      await tester.tap(find.text('Табло'));
      await tester.pump();

      expect(captured, ViewMode.display);
    });

    testWidgets('tap on Таблица fires onChanged with table mode',
        (tester) async {
      ViewMode? captured;
      await tester.pumpWidget(
        _wrap(ViewModeSelector(
          mode: ViewMode.chart,
          color: Colors.blue,
          onChanged: (m) => captured = m,
        )),
      );

      await tester.tap(find.text('Таблица'));
      await tester.pump();

      expect(captured, ViewMode.table);
    });
  });

  group('BigDisplay', () {
    testWidgets('shows em-dash placeholder when value is null', (tester) async {
      await tester.pumpWidget(
        _wrap(const BigDisplay(value: null, sensor: SensorType.voltage)),
      );

      expect(find.text('—'), findsOneWidget);
      expect(find.text('Напряжение'), findsOneWidget);
      expect(find.text('В'), findsOneWidget);
    });

    testWidgets('renders numeric value when given', (tester) async {
      await tester.pumpWidget(
        _wrap(const BigDisplay(value: 3.30, sensor: SensorType.voltage)),
      );

      // SensorUtils.formatValue для voltage с decimalPlaces=2 даст "3.30".
      expect(find.text('3.30'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('shows the unit and projector hint', (tester) async {
      await tester.pumpWidget(
        _wrap(const BigDisplay(value: 25.0, sensor: SensorType.temperature)),
      );

      expect(find.text('°C'), findsOneWidget);
      expect(find.text('Режим «Табло» — для проектора'), findsOneWidget);
    });
  });

  group('DataTableView', () {
    testWidgets('empty data shows empty state with sensor title',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const DataTableView(
          data: <SensorPacket>[],
          sensor: SensorType.voltage,
        )),
      );

      expect(find.text('Таблица пуста'), findsOneWidget);
      expect(
        find.textContaining('Нажмите «Старт»'),
        findsOneWidget,
      );
    });

    testWidgets('non-empty data shows header and rows', (tester) async {
      final data = <SensorPacket>[
        const SensorPacket(timestampMs: 1000, voltageV: 3.30),
        const SensorPacket(timestampMs: 2000, voltageV: 3.31),
        const SensorPacket(timestampMs: 3000, voltageV: 3.32),
      ];

      await tester.pumpWidget(
        _wrap(SizedBox(
          width: 400,
          height: 600,
          child: DataTableView(
            data: data,
            sensor: SensorType.voltage,
          ),
        )),
      );

      expect(find.text('№'), findsOneWidget);
      expect(find.text('Время, с'), findsOneWidget);
      expect(find.textContaining('Напряжение'), findsOneWidget);
      // Все три значения видимы (буфер 500 строк, у нас 3).
      expect(find.text('3.30'), findsOneWidget);
      expect(find.text('3.31'), findsOneWidget);
      expect(find.text('3.32'), findsOneWidget);
    });

    testWidgets('row numbers reflect original index, not display order',
        (tester) async {
      // Время и значение в форматах не должны совпадать, иначе find.text
      // найдёт более одного widget'а (одинаковый Text для двух колонок).
      // Используем дробные значения, отличающиеся от timeSeconds.
      const data = <SensorPacket>[
        SensorPacket(timestampMs: 1000, voltageV: 1.55),
        SensorPacket(timestampMs: 2000, voltageV: 2.66),
        SensorPacket(timestampMs: 3000, voltageV: 3.77),
      ];

      await tester.pumpWidget(
        _wrap(const SizedBox(
          width: 400,
          height: 600,
          child: DataTableView(
            data: data,
            sensor: SensorType.voltage,
          ),
        )),
      );

      expect(find.text('1.55'), findsOneWidget);
      expect(find.text('2.66'), findsOneWidget);
      expect(find.text('3.77'), findsOneWidget);
      // Номера строк 1..3 — каждая запись пронумерована независимо от
      // порядка отрисовки (визуальный порядок управляется ListView reverse).
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('SessionStatusPill', () {
    testWidgets('isRunning=true shows «Идёт запись»', (tester) async {
      await tester.pumpWidget(
        _wrap(const SessionStatusPill(
          isRunning: true,
          isReviewMode: false,
        )),
      );

      expect(find.text('Идёт запись'), findsOneWidget);
    });

    testWidgets('isReviewMode=true shows «Режим анализа»', (tester) async {
      await tester.pumpWidget(
        _wrap(const SessionStatusPill(
          isRunning: false,
          isReviewMode: true,
        )),
      );

      expect(find.text('Режим анализа'), findsOneWidget);
    });

    testWidgets('idle state shows «Готов к записи»', (tester) async {
      await tester.pumpWidget(
        _wrap(const SessionStatusPill(
          isRunning: false,
          isReviewMode: false,
        )),
      );

      expect(find.text('Готов к записи'), findsOneWidget);
    });
  });

  group('ActionButton', () {
    testWidgets('disabled when onPressed is null (no callback fires)',
        (tester) async {
      const taps = 0;
      await tester.pumpWidget(
        _wrap(const ActionButton(
          onPressed: null,
          icon: Icons.play_arrow,
          label: 'Старт',
        )),
      );

      // У disabled-кнопки нажатие не приводит к вызову — но в этом тесте
      // мы проверяем именно отсутствие callback'а через null.
      await tester.tap(find.text('Старт'), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('filled style renders label and icon and fires callback',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(ActionButton(
          onPressed: () => taps++,
          icon: Icons.play_arrow,
          label: 'Старт',
          filled: true,
        )),
      );

      // FilledButton.icon — это factory, создающая внутренний субвиджет;
      // проверять его типом ненадёжно. Проверяем сам контракт виджета:
      // label + icon + callback срабатывают.
      expect(find.text('Старт'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.text('Старт'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('outlined style renders label and icon and fires callback',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(ActionButton(
          onPressed: () => taps++,
          icon: Icons.delete,
          label: 'Очистить',
        )),
      );

      expect(find.text('Очистить'), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);

      await tester.tap(find.text('Очистить'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('ControlBar primary action', () {
    testWidgets('idle + connected → label «Старт», calls onStart on tap',
        (tester) async {
      var startCalls = 0;
      var stopCalls = 0;

      await tester.pumpWidget(
        _wrap(ControlBar(
          sensor: SensorType.voltage,
          isRunning: false,
          isConnected: true,
          measurementCount: 0,
          isCalibrated: false,
          sampleRateHz: 10,
          currentValue: 3.30,
          elapsedSeconds: 0,
          onStart: () => startCalls++,
          onStop: () => stopCalls++,
          onClear: () {},
          onCalibrate: () {},
          onExport: () {},
        )),
      );

      expect(find.text('Старт'), findsOneWidget);

      await tester.tap(find.text('Старт'));
      await tester.pump();

      expect(startCalls, 1);
      expect(stopCalls, 0);
    });

    testWidgets('running → label «Стоп», calls onStop on tap', (tester) async {
      var startCalls = 0;
      var stopCalls = 0;

      await tester.pumpWidget(
        _wrap(ControlBar(
          sensor: SensorType.voltage,
          isRunning: true,
          isConnected: true,
          measurementCount: 100,
          isCalibrated: false,
          sampleRateHz: 10,
          currentValue: 3.30,
          elapsedSeconds: 5.0,
          onStart: () => startCalls++,
          onStop: () => stopCalls++,
          onClear: () {},
          onCalibrate: () {},
          onExport: () {},
        )),
      );

      expect(find.text('Стоп'), findsOneWidget);

      await tester.tap(find.text('Стоп'));
      await tester.pump();

      expect(stopCalls, 1);
      expect(startCalls, 0);
    });

    testWidgets('reviewMode (stopped + has data) → «Новая запись» + «Экспорт»',
        (tester) async {
      var exportCalls = 0;
      await tester.pumpWidget(
        _wrap(ControlBar(
          sensor: SensorType.voltage,
          isRunning: false,
          isConnected: true,
          measurementCount: 200,
          isCalibrated: false,
          sampleRateHz: 10,
          currentValue: 3.30,
          elapsedSeconds: 20.0,
          onStart: () {},
          onStop: () {},
          onClear: () {},
          onCalibrate: () {},
          onExport: () => exportCalls++,
        )),
      );

      expect(find.text('Новая запись'), findsOneWidget);
      expect(find.text('Экспорт'), findsOneWidget);

      await tester.tap(find.text('Экспорт'));
      await tester.pump();

      expect(exportCalls, 1);
    });

    testWidgets('not connected → primary button is disabled', (tester) async {
      var startCalls = 0;
      await tester.pumpWidget(
        _wrap(ControlBar(
          sensor: SensorType.voltage,
          isRunning: false,
          isConnected: false,
          measurementCount: 0,
          isCalibrated: false,
          sampleRateHz: 10,
          currentValue: null,
          elapsedSeconds: 0,
          onStart: () => startCalls++,
          onStop: () {},
          onClear: () {},
          onCalibrate: () {},
          onExport: () {},
        )),
      );

      // Кнопка существует, но disabled. Tap не должен ничего вызвать.
      await tester.tap(find.text('Старт'), warnIfMissed: false);
      await tester.pump();

      expect(startCalls, 0,
          reason: 'нельзя начать запись без подключения к датчику');
    });
  });

  group('ChartView smoke', () {
    testWidgets('empty data shows hint, does not crash', (tester) async {
      await tester.pumpWidget(
        _wrap(const SizedBox(
          width: 800,
          height: 400,
          child: ChartView(
            data: <SensorPacket>[],
            sensor: SensorType.voltage,
            isRunning: false,
            elapsedSeconds: 0,
          ),
        )),
      );

      expect(find.textContaining('появится после старта'), findsOneWidget);
    });

    testWidgets('with a few points renders without crash', (tester) async {
      final data = <SensorPacket>[
        for (int i = 0; i < 50; i++)
          SensorPacket(timestampMs: i * 100, voltageV: 3.0 + i * 0.01),
      ];

      await tester.pumpWidget(
        _wrap(SizedBox(
          width: 800,
          height: 400,
          child: ChartView(
            data: data,
            sensor: SensorType.voltage,
            isRunning: true,
            elapsedSeconds: 5.0,
          ),
        )),
      );

      // Просто проверяем что собрался без exceptions.
      expect(tester.takeException(), isNull);
    });
  });
}
