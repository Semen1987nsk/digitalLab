import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/entities/calibration_data.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/entities/sensor_type.dart';
import '../../../domain/math/lttb.dart';
import '../../../domain/utils/sensor_utils.dart';
import '../../themes/app_theme.dart';
import 'stopped_review_widgets.dart';

/// Снимок видимых точек графика + заранее посчитанные границы Y.
///
/// Собирается за один проход (`ChartView._collectSpotsAndBounds`):
/// сразу даёт `FlSpot` без промежуточного `DataPoint`, плюс minY/maxY —
/// нет двух дополнительных проходов по массиву.
class ChartData {
  final List<FlSpot> spots;
  final double minY;
  final double maxY;
  const ChartData(this.spots, this.minY, this.maxY);
}

/// Режим взаимодействия с графиком (вне записи):
/// - [pan] — drag перемещает окно по времени, scale — зум.
/// - [selectZoom] — пользователь выделяет прямоугольник на графике,
///   при отпускании окно зумируется на этот участок.
enum ChartInteractionMode { pan, selectZoom }

/// Y(t)-график эксперимента с LTTB-downsampling, авто-масштабом оси Y и
/// панелью «Stopped Review» (вне записи) для зума/выбора участка.
class ChartView extends StatefulWidget {
  final List<SensorPacket> data;
  final SensorType sensor;
  final bool isRunning;

  /// Wall-clock elapsed seconds (30 FPS) для плавной X-прокрутки.
  final double elapsedSeconds;

  /// Программная калибровка напряжения (null = без калибровки).
  final VoltageCalibration? voltageCalibration;

  const ChartView({
    super.key,
    required this.data,
    required this.sensor,
    required this.isRunning,
    required this.elapsedSeconds,
    this.voltageCalibration,
  });

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> {
  static const double _visibleWindowSec = 30.0;
  static const double _shrinkAlpha = 0.12;
  static const double _xSnapStepSec = 0.5;
  static const int _downsampleThreshold = 5000;
  static const int _maxRenderPoints = 1200;
  static const double _minWindowSec = 0.5;
  static const double _panFractionStep = 0.25;
  static const double _zoomFactorIn = 0.7;
  static const double _zoomFactorOut = 1.4;
  static const double _minSelectionLogicalWidth = 0.2;
  static const double _minSelectionScreenWidth = 12.0;
  static const double _chartLeftReservedPx = 48.0;

  double? _stableMinY;
  double? _stableMaxY;

  // ── UX: Pan & Zoom State ──
  double? _userMinX;
  double? _userMaxX;
  double? _userMinY;
  double? _userMaxY;
  double _startMinX = 0;
  double _startMaxX = 0;
  double _scaleStartFocalDx = 0;
  ChartInteractionMode _interactionMode = ChartInteractionMode.pan;
  int? _selectionPointerId;
  double? _selectionStartDx;
  double? _selectionCurrentDx;

  @override
  void didUpdateWidget(covariant ChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sensor != widget.sensor) {
      _stableMinY = null;
      _stableMaxY = null;
      _userMinX = null;
      _userMaxX = null;
      _userMinY = null;
      _userMaxY = null;
    }
    if (widget.isRunning && !oldWidget.isRunning) {
      _userMinX = null;
      _userMaxX = null;
      _userMinY = null;
      _userMaxY = null;
      _interactionMode = ChartInteractionMode.pan;
    }
  }

  bool get _hasManualXRange => _userMinX != null && _userMaxX != null;
  bool get _hasManualYRange => _userMinY != null && _userMaxY != null;
  bool get _hasSelectionPreview =>
      _selectionStartDx != null && _selectionCurrentDx != null;

  ({double minX, double maxX}) _clampXWindow({
    required double minX,
    required double maxX,
    required double maxDataTime,
  }) {
    double newMinX = minX;
    double newMaxX = maxX;
    double range = newMaxX - newMinX;

    if (!range.isFinite || range <= 0) {
      range = math.min(_visibleWindowSec, math.max(maxDataTime, _minWindowSec));
      newMinX = math.max(0.0, maxDataTime - range);
      newMaxX = newMinX + range;
    }

    if (range < _minWindowSec) {
      final center = (newMinX + newMaxX) / 2;
      range = _minWindowSec;
      newMinX = center - range / 2;
      newMaxX = center + range / 2;
    }

    if (range > maxDataTime && maxDataTime > 0) {
      range = maxDataTime;
      newMinX = 0;
      newMaxX = maxDataTime;
    }

    if (newMinX < 0) {
      newMinX = 0;
      newMaxX = newMinX + range;
    }
    if (newMaxX > maxDataTime) {
      newMaxX = maxDataTime;
      newMinX = newMaxX - range;
      if (newMinX < 0) newMinX = 0;
    }

    return (minX: newMinX, maxX: newMaxX);
  }

  void _resetView() {
    setState(() {
      _userMinX = null;
      _userMaxX = null;
      _userMinY = null;
      _userMaxY = null;
      _stableMinY = null;
      _stableMaxY = null;
      _selectionPointerId = null;
      _selectionStartDx = null;
      _selectionCurrentDx = null;
      _interactionMode = ChartInteractionMode.pan;
    });
  }

  double _clampChartDx(double dx, double chartWidth) {
    return dx.clamp(_chartLeftReservedPx, _chartLeftReservedPx + chartWidth);
  }

  void _clearSelectionPreview() {
    if (!_hasSelectionPreview && _selectionPointerId == null) return;
    setState(() {
      _selectionPointerId = null;
      _selectionStartDx = null;
      _selectionCurrentDx = null;
    });
  }

  void _toggleInteractionMode(ChartInteractionMode mode) {
    setState(() {
      _interactionMode = mode;
      _selectionPointerId = null;
      _selectionStartDx = null;
      _selectionCurrentDx = null;
    });
  }

  bool _canStartSelection(PointerDownEvent event) {
    if (widget.isRunning ||
        _interactionMode != ChartInteractionMode.selectZoom) {
      return false;
    }

    if (event.kind == PointerDeviceKind.mouse) {
      return (event.buttons & kPrimaryMouseButton) != 0;
    }

    return event.buttons != 0;
  }

  void _handleSelectionPointerDown(PointerDownEvent event, double chartWidth) {
    if (!_canStartSelection(event) || chartWidth <= 0) {
      return;
    }

    if (event.localPosition.dx < _chartLeftReservedPx ||
        event.localPosition.dx > _chartLeftReservedPx + chartWidth) {
      return;
    }

    final startDx = _clampChartDx(event.localPosition.dx, chartWidth);
    setState(() {
      _selectionPointerId = event.pointer;
      _selectionStartDx = startDx;
      _selectionCurrentDx = startDx;
    });
  }

  void _handleSelectionPointerMove(PointerMoveEvent event, double chartWidth) {
    if (chartWidth <= 0 || _selectionPointerId != event.pointer) {
      return;
    }

    setState(() {
      _selectionCurrentDx = _clampChartDx(event.localPosition.dx, chartWidth);
    });
  }

  void _handleSelectionPointerEnd(
    int pointer,
    double chartWidth,
    double minVisibleX,
    double maxX,
    double maxDataTime,
  ) {
    if (_selectionPointerId != pointer) {
      return;
    }

    if (chartWidth <= 0) {
      _clearSelectionPreview();
      return;
    }

    _applySelectionZoom(chartWidth, minVisibleX, maxX, maxDataTime);
  }

  void _applySelectionZoom(
    double chartWidth,
    double minVisibleX,
    double maxX,
    double maxDataTime,
  ) {
    final startDx = _selectionStartDx;
    final currentDx = _selectionCurrentDx;
    if (startDx == null || currentDx == null) return;

    final leftDx = math.min(startDx, currentDx);
    final rightDx = math.max(startDx, currentDx);
    final screenWidth = rightDx - leftDx;

    if (screenWidth < _minSelectionScreenWidth || chartWidth <= 0) {
      _clearSelectionPreview();
      return;
    }

    final range = maxX - minVisibleX;
    final startFraction =
        ((leftDx - _chartLeftReservedPx) / chartWidth).clamp(0.0, 1.0);
    final endFraction =
        ((rightDx - _chartLeftReservedPx) / chartWidth).clamp(0.0, 1.0);

    final selectedMinX = minVisibleX + range * startFraction;
    final selectedMaxX = minVisibleX + range * endFraction;
    final selectedWidth = selectedMaxX - selectedMinX;

    if (selectedWidth < _minSelectionLogicalWidth) {
      _clearSelectionPreview();
      return;
    }

    final clamped = _clampXWindow(
      minX: selectedMinX,
      maxX: selectedMaxX,
      maxDataTime: math.max(maxDataTime, _minWindowSec),
    );

    setState(() {
      _userMinX = clamped.minX;
      _userMaxX = clamped.maxX;
      _userMinY = null;
      _userMaxY = null;
      _stableMinY = null;
      _stableMaxY = null;
      _selectionPointerId = null;
      _selectionStartDx = null;
      _selectionCurrentDx = null;
      _interactionMode = ChartInteractionMode.pan;
    });
  }

  void _fitAllX(double maxDataTime) {
    final clamped = _clampXWindow(
      minX: 0,
      maxX: math.max(maxDataTime, _minWindowSec),
      maxDataTime: math.max(maxDataTime, _minWindowSec),
    );
    setState(() {
      _userMinX = clamped.minX;
      _userMaxX = clamped.maxX;
      _userMinY = null;
      _userMaxY = null;
      _stableMinY = null;
      _stableMaxY = null;
    });
  }

  void _setXWindowFromStart(double startX, double range, double maxDataTime) {
    final clamped = _clampXWindow(
      minX: startX,
      maxX: startX + range,
      maxDataTime: math.max(maxDataTime, _minWindowSec),
    );
    setState(() {
      _userMinX = clamped.minX;
      _userMaxX = clamped.maxX;
    });
  }

  void _panByFraction(
      double fraction, double minVisibleX, double maxX, double maxDataTime) {
    final currentMin = _userMinX ?? minVisibleX;
    final currentMax = _userMaxX ?? maxX;
    final range = currentMax - currentMin;
    final shift = range * fraction;
    final clamped = _clampXWindow(
      minX: currentMin + shift,
      maxX: currentMax + shift,
      maxDataTime: math.max(maxDataTime, _minWindowSec),
    );
    setState(() {
      _userMinX = clamped.minX;
      _userMaxX = clamped.maxX;
    });
  }

  void _zoomXByFactor(
    double factor,
    double minVisibleX,
    double maxX,
    double maxDataTime, {
    double anchorFraction = 0.5,
  }) {
    final currentMin = _userMinX ?? minVisibleX;
    final currentMax = _userMaxX ?? maxX;
    final currentRange = currentMax - currentMin;
    final targetRange = (currentRange * factor)
        .clamp(_minWindowSec, math.max(maxDataTime, _minWindowSec));
    final center = currentMin + currentRange * anchorFraction;
    final clamped = _clampXWindow(
      minX: center - targetRange * anchorFraction,
      maxX: center + targetRange * (1 - anchorFraction),
      maxDataTime: math.max(maxDataTime, _minWindowSec),
    );
    setState(() {
      _userMinX = clamped.minX;
      _userMaxX = clamped.maxX;
    });
  }

  void _zoomYByFactor(double factor, double currentMinY, double currentMaxY) {
    final currentRange = (currentMaxY - currentMinY).abs();
    final safeRange = currentRange < widget.sensor.minRange
        ? widget.sensor.minRange
        : currentRange;
    final targetRange = (safeRange * factor).clamp(
      widget.sensor.minRange,
      widget.sensor.minRange * 500,
    );
    final center = (currentMinY + currentMaxY) / 2;

    setState(() {
      _userMinY = center - targetRange / 2;
      _userMaxY = center + targetRange / 2;
    });
  }

  void _resetYScale() {
    setState(() {
      _userMinY = null;
      _userMaxY = null;
      _stableMinY = null;
      _stableMaxY = null;
    });
  }

  /// Авто-масштаб оси Y: expand мгновенно, shrink плавно (EMA).
  ///
  /// Ось Y отслеживает видимый диапазон данных (Vernier LabQuest, PASCO
  /// Capstone, LabVIEW). MIN и MAX обрабатываются независимо: если данные
  /// прижаты к нижнему краю, верхний край всё равно может плавно сужаться
  /// (и наоборот). Скорость сужения — α=0.02 при записи (~3 с до 85%
  /// сходимости при 30 FPS), α=0.12 в режиме анализа (~0.3 с).
  void _updateStableRange(double rawMin, double rawMax) {
    if (!rawMin.isFinite || !rawMax.isFinite) return;

    if (_stableMinY == null || _stableMaxY == null) {
      _stableMinY = rawMin;
      _stableMaxY = rawMax;
      return;
    }

    final currentMin = _stableMinY!;
    final currentMax = _stableMaxY!;
    final currentRange = (currentMax - currentMin).abs();
    final safeRange = currentRange < widget.sensor.minRange
        ? widget.sensor.minRange
        : currentRange;

    final hysteresis = safeRange * 0.10;
    final alpha = widget.isRunning ? 0.02 : _shrinkAlpha;

    if (rawMin < currentMin + hysteresis) {
      _stableMinY = math.min(currentMin, rawMin);
    } else {
      _stableMinY = currentMin + (rawMin - currentMin) * alpha;
    }

    if (rawMax > currentMax - hysteresis) {
      _stableMaxY = math.max(currentMax, rawMax);
    } else {
      _stableMaxY = currentMax + (rawMax - currentMax) * alpha;
    }

    final stableRange = (_stableMaxY! - _stableMinY!).abs();
    if (stableRange < widget.sensor.minRange) {
      final center = (_stableMaxY! + _stableMinY!) / 2;
      _stableMinY = center - widget.sensor.minRange / 2;
      _stableMaxY = center + widget.sensor.minRange / 2;
    }
  }

  /// Сбор точек видимого окна + LTTB при необходимости + Y-bounds — за один проход.
  ///
  /// Оптимизации (senior level):
  /// - FlSpot напрямую (без промежуточного DataPoint)
  /// - min/max Y в том же цикле (−2 прохода по массиву)
  /// - LTTB при > [_downsampleThreshold] точек (с оконным снэпшотом редко)
  ChartData? _collectSpotsAndBounds(
    List<SensorPacket> data,
    double minVisibleX,
    double maxVisibleX,
  ) {
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    final reversed = <FlSpot>[];
    for (int i = data.length - 1; i >= 0; i--) {
      final p = data[i];
      if (p.timeSeconds < minVisibleX) break;
      if (p.timeSeconds > maxVisibleX) continue;
      final v = SensorUtils.getCalibratedValue(p, widget.sensor,
          voltageCalibration: widget.voltageCalibration);
      if (v == null || !v.isFinite) continue;
      reversed.add(FlSpot(p.timeSeconds, v));
      if (v < minY) minY = v;
      if (v > maxY) maxY = v;
    }

    if (reversed.isEmpty) return null;
    final spots = reversed.reversed.toList(growable: false);

    if (spots.length > _downsampleThreshold) {
      final Float64List dataPoints = Float64List(spots.length * 2);
      for (int i = 0; i < spots.length; i++) {
        dataPoints[i * 2] = spots[i].x;
        dataPoints[i * 2 + 1] = spots[i].y;
      }

      final Float64List downsampled =
          LTTB.downsample(dataPoints, _maxRenderPoints);
      minY = double.infinity;
      maxY = double.negativeInfinity;

      final int dsLength = downsampled.length ~/ 2;
      final dsSpots = List<FlSpot>.generate(dsLength, (i) {
        final double x = downsampled[i * 2];
        final double y = downsampled[i * 2 + 1];
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        return FlSpot(x, y);
      }, growable: false);
      return ChartData(dsSpots, minY, maxY);
    }

    return ChartData(spots, minY, maxY);
  }

  double _snapDown(double value, double step) {
    if (!value.isFinite || step <= 0) return value;
    return (value / step).floor() * step;
  }

  double _snapUp(double value, double step) {
    if (!value.isFinite || step <= 0) return value;
    return (value / step).ceil() * step;
  }

  /// «Красивый» шаг оси (1-2-5 × 10^n) по алгоритму Heckbert 1990.
  ///
  /// Пороги — геометрические средние между соседними «красивыми» числами:
  ///   √(1×2) ≈ 1.5,  √(2×5) ≈ 3.16,  √(5×10) ≈ 7.07
  double _niceStep(double rawStep) {
    if (!rawStep.isFinite || rawStep <= 0) return 1.0;
    final exponent = math.pow(10.0, (math.log(rawStep) / math.ln10).floor());
    final fraction = rawStep / exponent;

    final double niceFraction;
    if (fraction < 1.5) {
      niceFraction = 1.0;
    } else if (fraction < 3.0) {
      niceFraction = 2.0;
    } else if (fraction < 7.0) {
      niceFraction = 5.0;
    } else {
      niceFraction = 10.0;
    }
    return niceFraction * exponent;
  }

  int _decimalPlacesForStep(double step) {
    if (!step.isFinite || step <= 0) return 1;
    final logVal = -(math.log(step) / math.ln10).floor();
    return logVal.clamp(0, 4);
  }

  /// «Красивый» шаг оси времени из расширенной последовательности
  /// {0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60} — человеку привычны 15 и 30.
  double _niceTimeStep(double rawStep) {
    const steps = [
      0.1,
      0.2,
      0.5,
      1.0,
      2.0,
      5.0,
      10.0,
      15.0,
      30.0,
      60.0,
      120.0,
      300.0
    ];
    for (final s in steps) {
      if (s >= rawStep * 0.9) return s;
    }
    return steps.last;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.sensor.color.withValues(alpha: 0.18),
                      widget.sensor.color.withValues(alpha: 0.06),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.sensor.color.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.show_chart_rounded,
                  size: 40,
                  color: widget.sensor.color,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'График появится после старта',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Нажмите «Старт» внизу, чтобы начать запись. Вы сможете остановить в любой момент и затем масштабировать график колёсиком мыши или жестами.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      );
    }

    final latestX = widget.data.last.timeSeconds;

    // Плавная прокрутка по wall-clock (30 FPS).
    // maxX = elapsedSeconds + 1.0 → ~3% «будущего» в 30-секундном окне.
    // При остановке — snap к сетке.
    double maxX;
    double minVisibleX;
    if (widget.isRunning) {
      maxX = widget.elapsedSeconds + 1.0;
      minVisibleX = math.max(0.0, maxX - _visibleWindowSec);
    } else {
      if (_userMinX != null && _userMaxX != null) {
        minVisibleX = _userMinX!;
        maxX = _userMaxX!;
      } else {
        maxX = _snapUp(latestX, _xSnapStepSec);
        minVisibleX = math.max(
          0.0,
          _snapDown(latestX, _xSnapStepSec) - _visibleWindowSec,
        );
      }
    }

    // ~6 делений в окне — оптимально для оси времени.
    final xVisibleRange = maxX - minVisibleX;
    final xStep = _niceTimeStep(xVisibleRange / 6.0);
    final xDecimals = _decimalPlacesForStep(xStep);

    final chartData = _collectSpotsAndBounds(widget.data, minVisibleX, maxX);

    if (chartData == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sensors_off, size: 56, color: AppColors.textHint),
            SizedBox(height: 12),
            Text(
              'Нет данных для этого датчика',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final spots = chartData.spots;
    var minY = chartData.minY;
    var maxY = chartData.maxY;
    final range = maxY - minY;

    if (range < widget.sensor.minRange) {
      final center = (maxY + minY) / 2;
      minY = center - widget.sensor.minRange / 2;
      maxY = center + widget.sensor.minRange / 2;
    }

    final pad = (maxY - minY) * 0.06;
    _updateStableRange(minY - pad, maxY + pad);

    final chartMinYRaw = _userMinY ?? _stableMinY ?? (minY - pad);
    final chartMaxYRaw = _userMaxY ?? _stableMaxY ?? (maxY + pad);

    final rawAxisRange = (chartMaxYRaw - chartMinYRaw).abs();
    final yStep = _niceStep(rawAxisRange / 6.0);
    final chartMinY = _snapDown(chartMinYRaw, yStep);
    final chartMaxY = _snapUp(chartMaxYRaw, yStep);
    final yDecimals = _decimalPlacesForStep(yStep);

    final maxDataTime = widget.data.isNotEmpty
        ? widget.data.last.timeSeconds
        : _visibleWindowSec;
    final visibleDuration = (maxX - minVisibleX)
        .clamp(_minWindowSec, math.max(maxDataTime, _minWindowSec).toDouble())
        .toDouble();
    final timelineScrollableExtent =
        math.max(0.0, maxDataTime - visibleDuration).toDouble();
    final showTimelineNavigator =
        !widget.isRunning && timelineScrollableExtent > 0.25;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
        child: Column(
          children: [
            if (!widget.isRunning)
              StoppedReviewPanel(
                isSelectionMode:
                    _interactionMode == ChartInteractionMode.selectZoom,
                visibleRangeLabel:
                    'Сейчас видно: ${minVisibleX.toStringAsFixed(xDecimals)}–${maxX.toStringAsFixed(xDecimals)} с',
                onFitAll: () => _fitAllX(maxDataTime),
                onResetView: _resetView,
                onToggleSelectionMode: () => _toggleInteractionMode(
                  _interactionMode == ChartInteractionMode.selectZoom
                      ? ChartInteractionMode.pan
                      : ChartInteractionMode.selectZoom,
                ),
                onResetYScale: _resetYScale,
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final double chartWidth =
                            constraints.maxWidth - _chartLeftReservedPx;

                        return Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (event) {
                            _handleSelectionPointerDown(event, chartWidth);
                          },
                          onPointerMove: (event) {
                            _handleSelectionPointerMove(event, chartWidth);
                          },
                          onPointerUp: (event) {
                            _handleSelectionPointerEnd(
                              event.pointer,
                              chartWidth,
                              minVisibleX,
                              maxX,
                              maxDataTime,
                            );
                          },
                          onPointerCancel: (event) {
                            if (_selectionPointerId == event.pointer) {
                              _clearSelectionPreview();
                            }
                          },
                          onPointerSignal: (signal) {
                            if (widget.isRunning ||
                                signal is! PointerScrollEvent) {
                              return;
                            }

                            final pressedKeys =
                                HardwareKeyboard.instance.logicalKeysPressed;
                            final isShiftPressed = pressedKeys
                                    .contains(LogicalKeyboardKey.shiftLeft) ||
                                pressedKeys
                                    .contains(LogicalKeyboardKey.shiftRight);
                            final isCtrlPressed = pressedKeys
                                    .contains(LogicalKeyboardKey.controlLeft) ||
                                pressedKeys
                                    .contains(LogicalKeyboardKey.controlRight);

                            if (isShiftPressed) {
                              final fraction = signal.scrollDelta.dy > 0
                                  ? _panFractionStep / 2
                                  : -_panFractionStep / 2;
                              _panByFraction(
                                  fraction, minVisibleX, maxX, maxDataTime);
                              return;
                            }

                            if (isCtrlPressed) {
                              if (signal.scrollDelta.dy > 0) {
                                _zoomYByFactor(
                                    _zoomFactorOut, chartMinY, chartMaxY);
                              } else if (signal.scrollDelta.dy < 0) {
                                _zoomYByFactor(
                                    _zoomFactorIn, chartMinY, chartMaxY);
                              }
                              return;
                            }

                            if (signal.scrollDelta.dy > 0) {
                              _zoomXByFactor(_zoomFactorOut, minVisibleX, maxX,
                                  maxDataTime);
                            } else if (signal.scrollDelta.dy < 0) {
                              _zoomXByFactor(_zoomFactorIn, minVisibleX, maxX,
                                  maxDataTime);
                            }
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: () {
                              if (widget.isRunning) return;
                              _resetView();
                            },
                            onHorizontalDragStart: (details) {
                              if (widget.isRunning) return;
                              if (_interactionMode ==
                                  ChartInteractionMode.selectZoom) {
                                return;
                              }
                              _startMinX = _userMinX ?? minVisibleX;
                              _startMaxX = _userMaxX ?? maxX;
                            },
                            onHorizontalDragUpdate: (details) {
                              if (widget.isRunning) return;
                              if (_interactionMode ==
                                  ChartInteractionMode.selectZoom) {
                                return;
                              }
                              if (chartWidth <= 0) return;

                              final currentRange = _startMaxX - _startMinX;
                              final timeDelta =
                                  -(details.delta.dx / chartWidth) *
                                      currentRange;
                              final clamped = _clampXWindow(
                                minX: (_userMinX ?? _startMinX) + timeDelta,
                                maxX: (_userMaxX ?? _startMaxX) + timeDelta,
                                maxDataTime:
                                    math.max(maxDataTime, _minWindowSec),
                              );
                              setState(() {
                                _userMinX = clamped.minX;
                                _userMaxX = clamped.maxX;
                              });
                            },
                            onHorizontalDragEnd: (_) {
                              if (widget.isRunning) return;
                              if (_interactionMode ==
                                  ChartInteractionMode.selectZoom) {
                                return;
                              }
                            },
                            onHorizontalDragCancel: () {
                              if (_interactionMode ==
                                  ChartInteractionMode.selectZoom) {
                                return;
                              }
                            },
                            onScaleStart: (details) {
                              if (widget.isRunning) return;
                              if (_interactionMode ==
                                  ChartInteractionMode.selectZoom) {
                                return;
                              }
                              _startMinX = _userMinX ?? minVisibleX;
                              _startMaxX = _userMaxX ?? maxX;
                              _scaleStartFocalDx = details.localFocalPoint.dx;
                            },
                            onScaleUpdate: (details) {
                              if (widget.isRunning) return;
                              final double chartWidth =
                                  constraints.maxWidth - _chartLeftReservedPx;
                              if (chartWidth <= 0) return;

                              if (_interactionMode ==
                                  ChartInteractionMode.selectZoom) {
                                return;
                              }

                              final double startRange = _startMaxX - _startMinX;
                              final bool looksLikePan =
                                  (details.scale - 1.0).abs() < 0.02;

                              if (looksLikePan) {
                                final double deltaFraction =
                                    (_scaleStartFocalDx -
                                            details.localFocalPoint.dx) /
                                        chartWidth;
                                final clamped = _clampXWindow(
                                  minX: _startMinX + startRange * deltaFraction,
                                  maxX: _startMaxX + startRange * deltaFraction,
                                  maxDataTime:
                                      math.max(maxDataTime, _minWindowSec),
                                );
                                setState(() {
                                  _userMinX = clamped.minX;
                                  _userMaxX = clamped.maxX;
                                });
                                return;
                              }

                              double newRange = startRange / details.scale;
                              final double safeMaxDataTime =
                                  math.max(maxDataTime, _minWindowSec);
                              if (newRange < _minWindowSec) {
                                newRange = _minWindowSec;
                              }
                              if (newRange > safeMaxDataTime) {
                                newRange = safeMaxDataTime;
                              }

                              double focalX = details.localFocalPoint.dx - 48;
                              if (focalX < 0) focalX = 0;
                              if (focalX > chartWidth) focalX = chartWidth;

                              final double focalFraction = focalX / chartWidth;
                              final double logicalFocalStart =
                                  _startMinX + startRange * focalFraction;
                              final clamped = _clampXWindow(
                                minX: logicalFocalStart -
                                    newRange * focalFraction,
                                maxX: logicalFocalStart +
                                    newRange * (1 - focalFraction),
                                maxDataTime: safeMaxDataTime,
                              );

                              setState(() {
                                _userMinX = clamped.minX;
                                _userMaxX = clamped.maxX;
                              });
                            },
                            onScaleEnd: (_) {
                              if (widget.isRunning) return;
                              if (_interactionMode ==
                                  ChartInteractionMode.selectZoom) {
                                return;
                              }
                            },
                            child: MouseRegion(
                              cursor: !widget.isRunning &&
                                      _interactionMode ==
                                          ChartInteractionMode.selectZoom
                                  ? SystemMouseCursors.precise
                                  : SystemMouseCursors.basic,
                              child: Stack(
                                clipBehavior: Clip.hardEdge,
                                children: [
                                  LineChart(
                                    duration: widget.isRunning
                                        ? Duration.zero
                                        : const Duration(milliseconds: 250),
                                    LineChartData(
                                      clipData: const FlClipData.all(),
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: true,
                                        horizontalInterval: yStep,
                                        verticalInterval: xStep,
                                        getDrawingHorizontalLine: (_) =>
                                            const FlLine(
                                          color: AppColors.cardBorder,
                                          strokeWidth: 0.5,
                                        ),
                                        getDrawingVerticalLine: (_) =>
                                            const FlLine(
                                          color: AppColors.cardBorder,
                                          strokeWidth: 0.5,
                                        ),
                                      ),
                                      titlesData: FlTitlesData(
                                        bottomTitles: AxisTitles(
                                          axisNameSize: 20,
                                          axisNameWidget: const Text(
                                            'Время, с',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textHint),
                                          ),
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 24,
                                            interval: xStep,
                                            getTitlesWidget: (v, _) => Text(
                                              v.toStringAsFixed(xDecimals),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: AppColors.textHint,
                                              ),
                                            ),
                                          ),
                                        ),
                                        leftTitles: AxisTitles(
                                          axisNameSize: 24,
                                          axisNameWidget: Text(
                                            widget.sensor.axisLabel,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textHint,
                                            ),
                                          ),
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 48,
                                            interval: yStep,
                                            getTitlesWidget: (v, _) => Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 4),
                                              child: Text(
                                                v.toStringAsFixed(yDecimals),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.textHint,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        topTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false),
                                        ),
                                      ),
                                      borderData: FlBorderData(
                                        show: true,
                                        border: Border.all(
                                          color: AppColors.cardBorder,
                                          width: 0.5,
                                        ),
                                      ),
                                      minX: minVisibleX,
                                      maxX: maxX,
                                      minY: chartMinY,
                                      maxY: chartMaxY,
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: spots,
                                          isCurved: false,
                                          color: widget.sensor.color,
                                          barWidth: 2,
                                          isStrokeCapRound: true,
                                          dotData: const FlDotData(show: false),
                                          belowBarData: BarAreaData(
                                            show: true,
                                            color: widget.sensor.color
                                                .withValues(alpha: 0.06),
                                          ),
                                        ),
                                      ],
                                      lineTouchData: LineTouchData(
                                        enabled: !(!widget.isRunning &&
                                            _interactionMode ==
                                                ChartInteractionMode
                                                    .selectZoom),
                                        touchTooltipData: LineTouchTooltipData(
                                          getTooltipItems: (spots) =>
                                              spots.map((s) {
                                            return LineTooltipItem(
                                              '${s.y.toStringAsFixed(widget.sensor.defaultDecimalPlaces)} ${widget.sensor.unit}\n${s.x.toStringAsFixed(2)} с',
                                              TextStyle(
                                                color: widget.sensor.color,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!widget.isRunning &&
                                      (_hasManualXRange || _hasManualYRange))
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Material(
                                        color: AppColors.surfaceLight
                                            .withValues(alpha: 0.88),
                                        borderRadius: BorderRadius.circular(20),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          onTap: _resetView,
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.zoom_out_map,
                                                  size: 16,
                                                  color: AppColors.textPrimary,
                                                ),
                                                SizedBox(width: 6),
                                                Text(
                                                  'Сбросить вид',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!widget.isRunning && _hasSelectionPreview)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: Builder(
                                          builder: (context) {
                                            final startDx = _selectionStartDx!;
                                            final currentDx =
                                                _selectionCurrentDx!;
                                            final left =
                                                math.min(startDx, currentDx);
                                            final width =
                                                (startDx - currentDx).abs();
                                            return Stack(
                                              children: [
                                                Positioned(
                                                  left: left,
                                                  top: 0,
                                                  bottom: 0,
                                                  width: width,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary
                                                          .withValues(
                                                              alpha: 0.14),
                                                      border: Border.all(
                                                        color: AppColors.primary
                                                            .withValues(
                                                                alpha: 0.75),
                                                        width: 1.5,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  left: left,
                                                  top: 10,
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary
                                                          .withValues(
                                                              alpha: 0.95),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: const Text(
                                                      'Отпустите мышь, чтобы приблизить участок',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (showTimelineNavigator) ...[
              const SizedBox(height: 10),
              TimelineNavigator(
                totalDuration: math.max(maxDataTime, _minWindowSec).toDouble(),
                visibleStart: minVisibleX,
                visibleEnd: maxX,
                onChanged: (newStart) => _setXWindowFromStart(
                    newStart, visibleDuration, maxDataTime),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mini-map тайм-линии под графиком: показывает положение видимого окна
/// внутри полного эксперимента, drag/tap перемещают окно.
class TimelineNavigator extends StatelessWidget {
  final double totalDuration;
  final double visibleStart;
  final double visibleEnd;
  final ValueChanged<double> onChanged;

  const TimelineNavigator({
    super.key,
    required this.totalDuration,
    required this.visibleStart,
    required this.visibleEnd,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final visibleDuration =
        (visibleEnd - visibleStart).clamp(0.1, totalDuration);
    final scrollableExtent = math.max(0.0, totalDuration - visibleDuration);

    if (scrollableExtent <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${visibleStart.toStringAsFixed(1)}–${visibleEnd.toStringAsFixed(1)} с',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          Row(
            children: [
              const Text(
                '0 c',
                style: TextStyle(fontSize: 9, color: AppColors.textHint),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final trackWidth = constraints.maxWidth;
                    final viewportWidth = math.max(
                        36.0, trackWidth * (visibleDuration / totalDuration));
                    final travel = math.max(1.0, trackWidth - viewportWidth);
                    final viewportLeft =
                        (visibleStart / scrollableExtent).clamp(0.0, 1.0) *
                            travel;

                    double positionToStart(double left) {
                      final normalized = (left / travel).clamp(0.0, 1.0);
                      return scrollableExtent * normalized;
                    }

                    double desiredLeftFromPointer(double localDx) {
                      return (localDx - viewportWidth / 2).clamp(0.0, travel);
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        final desiredLeft =
                            desiredLeftFromPointer(details.localPosition.dx);
                        onChanged(positionToStart(desiredLeft));
                      },
                      onHorizontalDragUpdate: (details) {
                        final currentLeft =
                            desiredLeftFromPointer(details.localPosition.dx);
                        onChanged(positionToStart(currentLeft));
                      },
                      child: SizedBox(
                        height: 18,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.background
                                    .withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            Positioned(
                              left: viewportLeft,
                              top: 1,
                              child: Container(
                                width: viewportWidth,
                                height: 16,
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.65),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.drag_indicator_rounded,
                                        size: 12, color: AppColors.primary),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${totalDuration.toStringAsFixed(1)} c',
                style: const TextStyle(fontSize: 9, color: AppColors.textHint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
