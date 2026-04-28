import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/calibration_data.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/entities/sensor_type.dart';
import '../../../domain/math/lttb.dart';
import '../../../domain/utils/sensor_utils.dart';
import '../../blocs/calibration/voltage_calibration_provider.dart';
import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════
//  ОСЦИЛЛОГРАФ — Цифровой двухканальный осциллограф
//
//  Вдохновлено: Rigol DS1054Z, Keysight DSOX1204G, Siglent SDS1104
//
//  Возможности:
//  • 2 канала: CH1 (Напряжение), CH2 (Сила тока)
//  • Авто/Нормальный/Однократный режимы триггера
//  • Курсоры времени и напряжения
//  • Автоизмерения: Vpp, Vrms, Freq, Period, Duty
//  • Классическая осциллографическая сетка 10×8 делений
//  • LTTB-даунсэмплинг для производительности
//  • Фосфорный режим отображения
// ═══════════════════════════════════════════════════════════════════

// ── Модели данных ─────────────────────────────────────────────────

/// Канал осциллографа
enum OscChannel { ch1, ch2 }

/// Режим триггера
enum TriggerMode { auto, normal, single }

/// Тип фронта триггера
enum TriggerEdge { rising, falling }

/// Режим работы осциллографа
enum OscRunMode { run, stop, single }

/// Настройки одного канала
class ChannelSettings {
  final bool enabled;
  final SensorType sensorType;
  final double voltsPerDiv;
  final double offset; // В единицах датчика (смещение по вертикали)
  final Color color;

  const ChannelSettings({
    required this.enabled,
    required this.sensorType,
    required this.voltsPerDiv,
    this.offset = 0,
    required this.color,
  });

  ChannelSettings copyWith({
    bool? enabled,
    SensorType? sensorType,
    double? voltsPerDiv,
    double? offset,
    Color? color,
  }) =>
      ChannelSettings(
        enabled: enabled ?? this.enabled,
        sensorType: sensorType ?? this.sensorType,
        voltsPerDiv: voltsPerDiv ?? this.voltsPerDiv,
        offset: offset ?? this.offset,
        color: color ?? this.color,
      );
}

/// Настройки триггера
class TriggerSettings {
  final TriggerMode mode;
  final TriggerEdge edge;
  final OscChannel source;
  final double level;

  const TriggerSettings({
    this.mode = TriggerMode.auto,
    this.edge = TriggerEdge.rising,
    this.source = OscChannel.ch1,
    this.level = 0,
  });

  TriggerSettings copyWith({
    TriggerMode? mode,
    TriggerEdge? edge,
    OscChannel? source,
    double? level,
  }) =>
      TriggerSettings(
        mode: mode ?? this.mode,
        edge: edge ?? this.edge,
        source: source ?? this.source,
        level: level ?? this.level,
      );
}

/// Автоизмерения для одного канала
class ChannelMeasurements {
  final double? vpp;
  final double? vrms;
  final double? vmax;
  final double? vmin;
  final double? vavg;
  final double? frequency;
  final double? period;

  const ChannelMeasurements({
    this.vpp,
    this.vrms,
    this.vmax,
    this.vmin,
    this.vavg,
    this.frequency,
    this.period,
  });
}

// ── Предустановленные шкалы ───────────────────────────────────────

const _vDivSteps = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0];
const _tDivSteps = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0];

// ── Константы сетки ───────────────────────────────────────────────

const int _gridDivsX = 10;
const int _gridDivsY = 8;

// ═══════════════════════════════════════════════════════════════════
//  СТРАНИЦА ОСЦИЛЛОГРАФА
// ═══════════════════════════════════════════════════════════════════

class OscilloscopePage extends ConsumerStatefulWidget {
  const OscilloscopePage({super.key});

  @override
  ConsumerState<OscilloscopePage> createState() => _OscilloscopePageState();
}

class _OscilloscopePageState extends ConsumerState<OscilloscopePage> {
  // ── Состояние ──────────────────────────────────────────────────
  OscRunMode _runMode = OscRunMode.run;
  double _timePerDiv = 0.5; // секунд на деление
  int _tDivIndex = 7; // индекс в _tDivSteps

  var _ch1 = const ChannelSettings(
    enabled: true,
    sensorType: SensorType.voltage,
    voltsPerDiv: 2.0,
    color: AppColors.oscChannel1, // Жёлтый — классика осциллографа
  );

  var _ch2 = const ChannelSettings(
    enabled: false,
    sensorType: SensorType.current,
    voltsPerDiv: 0.2,
    color: AppColors.oscChannel2, // Голубой — канал 2
  );

  var _trigger = const TriggerSettings();

  bool _showMeasurements = true;
  bool _showCursors = false;

  // Курсоры (нормализованные 0..1)
  // ignore: prefer_final_fields
  double _cursorX1 = 0.3;
  // ignore: prefer_final_fields
  double _cursorX2 = 0.7;
  // ignore: prefer_final_fields
  double _cursorY1 = 0.35;
  // ignore: prefer_final_fields
  double _cursorY2 = 0.65;

  // Буфер данных
  final List<SensorPacket> _waveformBuffer = [];
  static const int _maxBufferSize = 20000;

  @override
  void initState() {
    super.initState();
    // Подписка на данные идёт через provider
  }

  /// Предыдущий снимок для сравнения
  int _lastDataLength = 0;

  /// Сколько точек уже синхронизировано из experiment.data в локальный буфер.
  /// Нужен для инкрементальной синхронизации без полного копирования списка.
  int _syncedExperimentLength = 0;

  @override
  Widget build(BuildContext context) {
    final experiment = ref.watch(experimentControllerProvider);
    final connectionState = ref.watch(sensorConnectionProvider);
    final isConnected = connectionState.status == ConnectionStatus.connected;

    // Программная калибровка напряжения (прокидывается в painter + measurements)
    final calState = ref.watch(voltageCalibrationProvider);
    final voltageCal =
        calState.calibration.isModified ? calState.calibration : null;

    // Обновляем буфер только когда данные действительно изменились
    if (experiment.data.length != _lastDataLength) {
      _lastDataLength = experiment.data.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateBuffer(experiment);
      });
    }

    return Scaffold(
      backgroundColor:
          AppColors.oscScreenBg, // Ещё темнее для экрана осциллографа
      appBar: _buildAppBar(isConnected),
      body: Column(
        children: [
          // ── Экран осциллографа ──────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: _OscilloscopeScreen(
                data: _waveformBuffer,
                ch1: _ch1,
                ch2: _ch2,
                timePerDiv: _timePerDiv,
                trigger: _trigger,
                showCursors: _showCursors,
                cursorX1: _cursorX1,
                cursorX2: _cursorX2,
                cursorY1: _cursorY1,
                cursorY2: _cursorY2,
                voltageCalibration: voltageCal,
              ),
            ),
          ),

          // ── Измерения ──────────────────────────────────────
          if (_showMeasurements)
            _MeasurementsBar(
              data: _waveformBuffer,
              ch1: _ch1,
              ch2: _ch2,
              timePerDiv: _timePerDiv,
              voltageCalibration: voltageCal,
            ),

          // ── Панель управления ───────────────────────────────
          _buildControlPanel(),
        ],
      ),
    );
  }

  void _updateBuffer(ExperimentState experiment) {
    if (_runMode == OscRunMode.stop) return;

    final data = experiment.data;

    // Эксперимент очищен/перезапущен — сбрасываем локальный буфер.
    if (data.isEmpty) {
      if (_waveformBuffer.isNotEmpty || _syncedExperimentLength != 0) {
        setState(() {
          _waveformBuffer.clear();
          _syncedExperimentLength = 0;
        });
      }
      return;
    }

    // История укоротилась (clear/start нового эксперимента) — полный ресинк.
    if (_syncedExperimentLength > data.length) {
      _syncedExperimentLength = 0;
      _waveformBuffer.clear();
    }

    // Нет новых точек.
    if (_syncedExperimentLength == data.length) return;

    final from = _syncedExperimentLength;
    final to = data.length;
    final chunk = data.sublist(from, to);

    setState(() {
      _waveformBuffer.addAll(chunk);
      _syncedExperimentLength = to;

      // Ограничиваем буфер
      if (_waveformBuffer.length > _maxBufferSize) {
        _waveformBuffer.removeRange(0, _waveformBuffer.length - _maxBufferSize);
      }

      if (_runMode == OscRunMode.single) {
        _runMode = OscRunMode.stop;
      }
    });
  }

  // ── AppBar ──────────────────────────────────────────────────────

  AppBar _buildAppBar(bool isConnected) {
    return AppBar(
      backgroundColor: AppColors.oscPanelBg,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _runMode == OscRunMode.run
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : AppColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _runMode == OscRunMode.run
                    ? AppColors.accent.withValues(alpha: 0.4)
                    : AppColors.error.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              _runMode == OscRunMode.run
                  ? '● RUN'
                  : _runMode == OscRunMode.single
                      ? '◉ SINGLE'
                      : '■ STOP',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: _runMode == OscRunMode.run
                    ? AppColors.accent
                    : AppColors.error,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Text('Осциллограф',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const Spacer(),
          // Метка: время/дел
          _InfoChip(
            label: 'T/дел',
            value: _formatTimeDiv(_timePerDiv),
            color: AppColors.textPrimary,
          ),
          const SizedBox(width: 8),
          if (_ch1.enabled)
            _InfoChip(
              label: 'CH1',
              value: _formatVoltDiv(_ch1.voltsPerDiv, _ch1.sensorType),
              color: _ch1.color,
            ),
          if (_ch1.enabled && _ch2.enabled) const SizedBox(width: 8),
          if (_ch2.enabled)
            _InfoChip(
              label: 'CH2',
              value: _formatVoltDiv(_ch2.voltsPerDiv, _ch2.sensorType),
              color: _ch2.color,
            ),
        ],
      ),
      actions: [
        // Измерения
        IconButton(
          onPressed: () =>
              setState(() => _showMeasurements = !_showMeasurements),
          icon: Icon(
            Icons.analytics_outlined,
            color: _showMeasurements ? AppColors.accent : AppColors.textHint,
          ),
          tooltip: 'Измерения',
        ),
        // Курсоры
        IconButton(
          onPressed: () => setState(() => _showCursors = !_showCursors),
          icon: Icon(
            Icons.straighten,
            color: _showCursors ? AppColors.warning : AppColors.textHint,
          ),
          tooltip: 'Курсоры',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ── Панель управления ───────────────────────────────────────────

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.oscPanelBg,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        children: [
          // Ряд 1: Основные кнопки
          Row(
            children: [
              // RUN / STOP
              _OscButton(
                label: _runMode == OscRunMode.run ? 'STOP' : 'RUN',
                icon: _runMode == OscRunMode.run
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                color: _runMode == OscRunMode.run
                    ? AppColors.error
                    : AppColors.accent,
                filled: true,
                onPressed: _toggleRunStop,
              ),
              const SizedBox(width: 6),
              // SINGLE
              _OscButton(
                label: 'SINGLE',
                icon: Icons.looks_one_outlined,
                color: AppColors.warning,
                onPressed: _singleTrigger,
              ),
              const SizedBox(width: 16),

              // Горизонтальная развёртка
              _ScaleControl(
                label: 'Развёртка',
                value: _formatTimeDiv(_timePerDiv),
                color: AppColors.textPrimary,
                onDecrease: _decreaseTimeDiv,
                onIncrease: _increaseTimeDiv,
              ),

              const SizedBox(width: 16),

              // CH1 шкала
              if (_ch1.enabled)
                _ScaleControl(
                  label: 'CH1',
                  value: _formatVoltDiv(_ch1.voltsPerDiv, _ch1.sensorType),
                  color: _ch1.color,
                  onDecrease: () => _changeVDiv(OscChannel.ch1, -1),
                  onIncrease: () => _changeVDiv(OscChannel.ch1, 1),
                ),

              if (_ch1.enabled && _ch2.enabled) const SizedBox(width: 16),

              // CH2 шкала
              if (_ch2.enabled)
                _ScaleControl(
                  label: 'CH2',
                  value: _formatVoltDiv(_ch2.voltsPerDiv, _ch2.sensorType),
                  color: _ch2.color,
                  onDecrease: () => _changeVDiv(OscChannel.ch2, -1),
                  onIncrease: () => _changeVDiv(OscChannel.ch2, 1),
                ),

              const Spacer(),

              // Кнопки каналов
              _ChannelToggle(
                label: 'CH1',
                color: _ch1.color,
                enabled: _ch1.enabled,
                onToggle: () => setState(
                    () => _ch1 = _ch1.copyWith(enabled: !_ch1.enabled)),
              ),
              const SizedBox(width: 6),
              _ChannelToggle(
                label: 'CH2',
                color: _ch2.color,
                enabled: _ch2.enabled,
                onToggle: () => setState(
                    () => _ch2 = _ch2.copyWith(enabled: !_ch2.enabled)),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Ряд 2: Триггер
          Row(
            children: [
              // Режим триггера
              const Text('Триггер:',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              _TriggerModeButton(
                mode: _trigger.mode,
                onChanged: (m) =>
                    setState(() => _trigger = _trigger.copyWith(mode: m)),
              ),
              const SizedBox(width: 12),
              // Фронт
              _OscChip(
                label:
                    _trigger.edge == TriggerEdge.rising ? '↗ Рост' : '↘ Спад',
                color: AppColors.warning,
                onTap: () => setState(() => _trigger = _trigger.copyWith(
                      edge: _trigger.edge == TriggerEdge.rising
                          ? TriggerEdge.falling
                          : TriggerEdge.rising,
                    )),
              ),
              const SizedBox(width: 12),
              // Источник
              _OscChip(
                label:
                    _trigger.source == OscChannel.ch1 ? 'Src: CH1' : 'Src: CH2',
                color:
                    _trigger.source == OscChannel.ch1 ? _ch1.color : _ch2.color,
                onTap: () => setState(() => _trigger = _trigger.copyWith(
                      source: _trigger.source == OscChannel.ch1
                          ? OscChannel.ch2
                          : OscChannel.ch1,
                    )),
              ),
              const Spacer(),
              // Уровень триггера
              const Text('Уровень:',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: Slider(
                  value: _trigger.level,
                  min: -10,
                  max: 10,
                  divisions: 200,
                  label: _trigger.level.toStringAsFixed(2),
                  activeColor: AppColors.warning,
                  onChanged: (v) =>
                      setState(() => _trigger = _trigger.copyWith(level: v)),
                ),
              ),
              Text(
                _trigger.level.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.warning,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Действия ────────────────────────────────────────────────────

  void _toggleRunStop() {
    final controller = ref.read(experimentControllerProvider.notifier);
    setState(() {
      if (_runMode == OscRunMode.run) {
        _runMode = OscRunMode.stop;
        controller.stop();
      } else {
        _runMode = OscRunMode.run;
        controller.start();
      }
    });
  }

  void _singleTrigger() {
    final controller = ref.read(experimentControllerProvider.notifier);
    setState(() {
      _runMode = OscRunMode.single;
      _waveformBuffer.clear();
      _syncedExperimentLength = 0;
      controller.start();
    });
  }

  void _increaseTimeDiv() {
    if (_tDivIndex < _tDivSteps.length - 1) {
      setState(() {
        _tDivIndex++;
        _timePerDiv = _tDivSteps[_tDivIndex];
      });
    }
  }

  void _decreaseTimeDiv() {
    if (_tDivIndex > 0) {
      setState(() {
        _tDivIndex--;
        _timePerDiv = _tDivSteps[_tDivIndex];
      });
    }
  }

  void _changeVDiv(OscChannel ch, int direction) {
    setState(() {
      if (ch == OscChannel.ch1) {
        final idx = _findClosestIndex(_vDivSteps, _ch1.voltsPerDiv) + direction;
        if (idx >= 0 && idx < _vDivSteps.length) {
          _ch1 = _ch1.copyWith(voltsPerDiv: _vDivSteps[idx]);
        }
      } else {
        final idx = _findClosestIndex(_vDivSteps, _ch2.voltsPerDiv) + direction;
        if (idx >= 0 && idx < _vDivSteps.length) {
          _ch2 = _ch2.copyWith(voltsPerDiv: _vDivSteps[idx]);
        }
      }
    });
  }

  int _findClosestIndex(List<double> steps, double value) {
    var best = 0;
    var bestDiff = (steps[0] - value).abs();
    for (var i = 1; i < steps.length; i++) {
      final diff = (steps[i] - value).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  String _formatTimeDiv(double sec) {
    if (sec < 0.001) return '${(sec * 1e6).toStringAsFixed(0)} мкс';
    if (sec < 1) return '${(sec * 1000).toStringAsFixed(0)} мс';
    return '${sec.toStringAsFixed(1)} с';
  }

  String _formatVoltDiv(double val, SensorType type) {
    if (val < 0.01) return '${(val * 1000).toStringAsFixed(1)} м${type.unit}';
    if (val < 1) return '${(val * 1000).toStringAsFixed(0)} м${type.unit}';
    return '${val.toStringAsFixed(val == val.roundToDouble() ? 0 : 1)} ${type.unit}';
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ЭКРАН ОСЦИЛЛОГРАФА — CustomPainter
// ═══════════════════════════════════════════════════════════════════

class _OscilloscopeScreen extends StatelessWidget {
  final List<SensorPacket> data;
  final ChannelSettings ch1;
  final ChannelSettings ch2;
  final double timePerDiv;
  final TriggerSettings trigger;
  final bool showCursors;
  final double cursorX1, cursorX2, cursorY1, cursorY2;
  final VoltageCalibration? voltageCalibration;

  const _OscilloscopeScreen({
    required this.data,
    required this.ch1,
    required this.ch2,
    required this.timePerDiv,
    required this.trigger,
    required this.showCursors,
    required this.cursorX1,
    required this.cursorX2,
    required this.cursorY1,
    required this.cursorY2,
    this.voltageCalibration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.oscScreenBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.oscScreenBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          painter: _OscPainter(
            data: data,
            ch1: ch1,
            ch2: ch2,
            timePerDiv: timePerDiv,
            trigger: trigger,
            showCursors: showCursors,
            cursorX1: cursorX1,
            cursorX2: cursorX2,
            cursorY1: cursorY1,
            cursorY2: cursorY2,
            voltageCalibration: voltageCalibration,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _OscPainter extends CustomPainter {
  final List<SensorPacket> data;
  final ChannelSettings ch1;
  final ChannelSettings ch2;
  final double timePerDiv;
  final TriggerSettings trigger;
  final bool showCursors;
  final double cursorX1, cursorX2, cursorY1, cursorY2;
  final VoltageCalibration? voltageCalibration;

  _OscPainter({
    required this.data,
    required this.ch1,
    required this.ch2,
    required this.timePerDiv,
    required this.trigger,
    required this.showCursors,
    required this.cursorX1,
    required this.cursorX2,
    required this.cursorY1,
    required this.cursorY2,
    this.voltageCalibration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawTriggerLevel(canvas, size);

    if (data.isNotEmpty) {
      if (ch1.enabled) _drawWaveform(canvas, size, ch1);
      if (ch2.enabled) _drawWaveform(canvas, size, ch2);
    }

    if (showCursors) _drawCursors(canvas, size);
    _drawChannelLabels(canvas, size);

    // Нет данных — подсказка
    if (data.isEmpty) {
      _drawNoData(canvas, size);
    }
  }

  /// Классическая осциллографическая сетка
  void _drawGrid(Canvas canvas, Size size) {
    final majorPaint = Paint()
      ..color = AppColors.oscGridMajor
      ..strokeWidth = 0.5;

    final minorPaint = Paint()
      ..color = AppColors.oscGridMinor
      ..strokeWidth = 0.3;

    final centerPaint = Paint()
      ..color = AppColors.oscGridCenter
      ..strokeWidth = 1.0;

    final dx = size.width / _gridDivsX;
    final dy = size.height / _gridDivsY;
    const tickLen = 4.0;

    // Мелкая сетка (5 подделений на деление)
    for (int i = 0; i <= _gridDivsX * 5; i++) {
      final x = i * dx / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorPaint);
    }
    for (int i = 0; i <= _gridDivsY * 5; i++) {
      final y = i * dy / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minorPaint);
    }

    // Основная сетка
    for (int i = 0; i <= _gridDivsX; i++) {
      final x = i * dx;
      final paint = i == _gridDivsX ~/ 2 ? centerPaint : majorPaint;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int i = 0; i <= _gridDivsY; i++) {
      final y = i * dy;
      final paint = i == _gridDivsY ~/ 2 ? centerPaint : majorPaint;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Засечки на центральных осях
    final tickPaint = Paint()
      ..color = AppColors.oscGridCenter
      ..strokeWidth = 0.8;

    // Горизонтальные засечки по центру Y
    final cy = size.height / 2;
    for (int i = 0; i <= _gridDivsX * 5; i++) {
      final x = i * dx / 5;
      canvas.drawLine(
          Offset(x, cy - tickLen), Offset(x, cy + tickLen), tickPaint);
    }

    // Вертикальные засечки по центру X
    final cx = size.width / 2;
    for (int i = 0; i <= _gridDivsY * 5; i++) {
      final y = i * dy / 5;
      canvas.drawLine(
          Offset(cx - tickLen, y), Offset(cx + tickLen, y), tickPaint);
    }
  }

  /// Рисуем линию уровня триггера
  void _drawTriggerLevel(Canvas canvas, Size size) {
    final ch = trigger.source == OscChannel.ch1 ? ch1 : ch2;
    if (!ch.enabled) return;

    final totalRange = ch.voltsPerDiv * _gridDivsY;
    final normalized = (trigger.level - ch.offset) / totalRange + 0.5;
    final y = (1 - normalized) * size.height;

    if (y < 0 || y > size.height) return;

    final paint = Paint()
      ..color = AppColors.warning.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Пунктирная линия
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    var startX = 0.0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, y),
        Offset(math.min(startX + dashWidth, size.width), y),
        paint,
      );
      startX += dashWidth + dashSpace;
    }

    // Треугольник-маркер триггера слева
    final markerPath = Path()
      ..moveTo(0, y - 6)
      ..lineTo(8, y)
      ..lineTo(0, y + 6)
      ..close();

    canvas.drawPath(
      markerPath,
      Paint()..color = AppColors.warning.withValues(alpha: 0.8),
    );
  }

  /// Рисуем сигнал канала
  void _drawWaveform(Canvas canvas, Size size, ChannelSettings ch) {
    if (data.isEmpty) return;

    // Временное окно
    final totalTime = timePerDiv * _gridDivsX;
    final lastTime = data.last.timeSeconds;
    final startTime = lastTime - totalTime;
    final startIndex = _lowerBoundByTime(startTime);

    // Фильтруем точки в окне + получаем значения
    final List<double> rawPoints = [];

    for (int i = startIndex; i < data.length; i++) {
      final packet = data[i];
      final t = packet.timeSeconds;

      final value = SensorUtils.getCalibratedValue(packet, ch.sensorType,
          voltageCalibration:
              ch.sensorType == SensorType.voltage ? voltageCalibration : null);
      if (value == null) continue;

      // Нормализуем время → X
      final x = ((t - startTime) / totalTime) * size.width;

      // Нормализуем значение → Y (центр = offset, масштаб = voltsPerDiv)
      final totalRange = ch.voltsPerDiv * _gridDivsY;
      final normalized = ((value - ch.offset) / totalRange) + 0.5;
      final y = (1 - normalized) * size.height;

      rawPoints.add(x);
      rawPoints.add(y.clamp(-10, size.height + 10).toDouble());
    }

    if (rawPoints.length < 4) return;

    // Ограничиваем количество рисуемых точек относительно ширины экрана.
    // Это критично для старых школьных ПК (CPU/GPU).
    final maxRenderPoints = math.max(600, (size.width * 1.5).round());
    final Float64List renderPoints = rawPoints.length > maxRenderPoints * 2
        ? LTTB.downsample(Float64List.fromList(rawPoints), maxRenderPoints)
        : Float64List.fromList(rawPoints);

    // Рисуем основную линию
    final path = Path()..moveTo(renderPoints[0], renderPoints[1]);
    for (int i = 2; i < renderPoints.length; i += 2) {
      path.lineTo(renderPoints[i], renderPoints[i + 1]);
    }

    // Свечение (glow) — фосфорный эффект
    final glowPaint = Paint()
      ..color = ch.color.withValues(alpha: 0.08)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glowPaint);

    // Основная линия
    final linePaint = Paint()
      ..color = ch.color.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(path, linePaint);

    // Яркий центр линии
    final brightPaint = Paint()
      ..color = ch.color.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, brightPaint);
  }

  /// Бинарный поиск первой точки, попадающей в видимое окно.
  int _lowerBoundByTime(double startTime) {
    int low = 0;
    int high = data.length;

    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (data[mid].timeSeconds < startTime) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    return low.clamp(0, data.length);
  }

  /// Курсоры
  void _drawCursors(Canvas canvas, Size size) {
    final cursorPaint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // X-курсоры (вертикальные, белые)
    cursorPaint.color = Colors.white.withValues(alpha: 0.6);
    final x1 = cursorX1 * size.width;
    final x2 = cursorX2 * size.width;
    _drawDashedLine(
        canvas, Offset(x1, 0), Offset(x1, size.height), cursorPaint);
    _drawDashedLine(
        canvas, Offset(x2, 0), Offset(x2, size.height), cursorPaint);

    // Y-курсоры (горизонтальные, зелёные)
    cursorPaint.color = AppColors.accent.withValues(alpha: 0.6);
    final y1 = cursorY1 * size.height;
    final y2 = cursorY2 * size.height;
    _drawDashedLine(canvas, Offset(0, y1), Offset(size.width, y1), cursorPaint);
    _drawDashedLine(canvas, Offset(0, y2), Offset(size.width, y2), cursorPaint);

    // Дельты
    final deltaT = (cursorX2 - cursorX1) * timePerDiv * _gridDivsX;
    final textPainter = TextPainter(
      text: TextSpan(
        text:
            'Δt = ${deltaT.toStringAsFixed(3)} с  f = ${deltaT > 0 ? (1 / deltaT).toStringAsFixed(1) : "∞"} Гц',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 11,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(x2 + 8, 8));
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dashLen = 5.0;
    const gapLen = 3.0;
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    final nx = dx / length;
    final ny = dy / length;
    var drawn = 0.0;
    while (drawn < length) {
      final start = Offset(from.dx + nx * drawn, from.dy + ny * drawn);
      drawn += dashLen;
      if (drawn > length) drawn = length;
      final end = Offset(from.dx + nx * drawn, from.dy + ny * drawn);
      canvas.drawLine(start, end, paint);
      drawn += gapLen;
    }
  }

  /// Метки каналов в углах
  void _drawChannelLabels(Canvas canvas, Size size) {
    var offsetY = 8.0;

    if (ch1.enabled) {
      _drawLabel(canvas, 'CH1: ${ch1.sensorType.title}', ch1.color,
          Offset(8, offsetY));
      offsetY += 18;
    }
    if (ch2.enabled) {
      _drawLabel(canvas, 'CH2: ${ch2.sensorType.title}', ch2.color,
          Offset(8, offsetY));
    }
  }

  void _drawLabel(Canvas canvas, String text, Color color, Offset pos) {
    final bgPaint = Paint()..color = color.withValues(alpha: 0.12);
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx, pos.dy, tp.width + 12, tp.height + 6),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, bgPaint);
    canvas.drawRRect(rect, borderPaint);
    tp.paint(canvas, Offset(pos.dx + 6, pos.dy + 3));
  }

  /// Нет данных
  void _drawNoData(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Нажмите ▶ RUN для начала захвата',
        style: TextStyle(
          color: AppColors.textHint,
          fontSize: 14,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas,
        Offset(
          (size.width - tp.width) / 2,
          (size.height - tp.height) / 2,
        ));
  }

  @override
  bool shouldRepaint(covariant _OscPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════
//  ПАНЕЛЬ АВТОИЗМЕРЕНИЙ
// ═══════════════════════════════════════════════════════════════════

class _MeasurementsBar extends StatelessWidget {
  final List<SensorPacket> data;
  final ChannelSettings ch1;
  final ChannelSettings ch2;
  final double timePerDiv;
  final VoltageCalibration? voltageCalibration;

  const _MeasurementsBar({
    required this.data,
    required this.ch1,
    required this.ch2,
    required this.timePerDiv,
    this.voltageCalibration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.oscPanelBg,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          if (ch1.enabled) ..._buildChannelMeasurements(ch1),
          if (ch1.enabled && ch2.enabled)
            Container(
              width: 1,
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: AppColors.cardBorder,
            ),
          if (ch2.enabled) ..._buildChannelMeasurements(ch2),
        ],
      ),
    );
  }

  List<Widget> _buildChannelMeasurements(ChannelSettings ch) {
    final m = _computeMeasurements(ch);
    return [
      _MeasItem(
          label: 'Vpp',
          value: m.vpp,
          unit: ch.sensorType.unit,
          color: ch.color),
      _MeasItem(
          label: 'Vrms',
          value: m.vrms,
          unit: ch.sensorType.unit,
          color: ch.color),
      _MeasItem(
          label: 'Max',
          value: m.vmax,
          unit: ch.sensorType.unit,
          color: ch.color),
      _MeasItem(
          label: 'Min',
          value: m.vmin,
          unit: ch.sensorType.unit,
          color: ch.color),
      _MeasItem(
          label: 'Avg',
          value: m.vavg,
          unit: ch.sensorType.unit,
          color: ch.color),
      _MeasItem(label: 'Freq', value: m.frequency, unit: 'Гц', color: ch.color),
    ];
  }

  ChannelMeasurements _computeMeasurements(ChannelSettings ch) {
    if (data.isEmpty) return const ChannelMeasurements();

    // Берём последние данные в окне
    final totalTime = timePerDiv * _gridDivsX;
    final lastTime = data.last.timeSeconds;
    final startTime = lastTime - totalTime;

    final values = <double>[];
    final times = <double>[];

    for (final p in data) {
      if (p.timeSeconds < startTime) continue;
      final v = SensorUtils.getCalibratedValue(p, ch.sensorType,
          voltageCalibration:
              ch.sensorType == SensorType.voltage ? voltageCalibration : null);
      if (v != null) {
        values.add(v);
        times.add(p.timeSeconds);
      }
    }

    if (values.isEmpty) return const ChannelMeasurements();

    final vmax = values.reduce(math.max);
    final vmin = values.reduce(math.min);
    final vpp = vmax - vmin;
    final vavg = values.reduce((a, b) => a + b) / values.length;

    // RMS
    final sumSq = values.fold<double>(0, (s, v) => s + v * v);
    final vrms = math.sqrt(sumSq / values.length);

    // Частота — считаем пересечения нуля (среднего)
    double? frequency;
    double? period;
    int crossings = 0;
    for (int i = 1; i < values.length; i++) {
      if ((values[i - 1] - vavg) * (values[i] - vavg) < 0) {
        crossings++;
      }
    }
    if (crossings >= 2 && times.length >= 2) {
      final duration = times.last - times.first;
      if (duration > 0) {
        // Полупериодов = crossings, периодов = crossings/2
        frequency = crossings / (2 * duration);
        period = 1 / frequency;
      }
    }

    return ChannelMeasurements(
      vpp: vpp,
      vrms: vrms,
      vmax: vmax,
      vmin: vmin,
      vavg: vavg,
      frequency: frequency,
      period: period,
    );
  }
}

class _MeasItem extends StatelessWidget {
  final String label;
  final double? value;
  final String unit;
  final Color color;

  const _MeasItem({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 9,
                color: color.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5),
          ),
          Text(
            value != null ? '${value!.toStringAsFixed(2)} $unit' : '—',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ
// ═══════════════════════════════════════════════════════════════════

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _OscButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onPressed;

  const _OscButton({
    required this.label,
    required this.icon,
    required this.color,
    this.filled = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
    );
  }
}

class _ScaleControl extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _ScaleControl({
    required this.label,
    required this.value,
    required this.color,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _scaleBtn(Icons.remove, onDecrease, color),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            constraints: const BoxConstraints(minWidth: 72),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 9,
                        color: color.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500)),
                Text(value,
                    style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          _scaleBtn(Icons.add, onIncrease, color),
        ],
      ),
    );
  }

  Widget _scaleBtn(IconData icon, VoidCallback onTap, Color c) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 38,
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: c.withValues(alpha: 0.7)),
      ),
    );
  }
}

class _ChannelToggle extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onToggle;

  const _ChannelToggle({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                enabled ? color.withValues(alpha: 0.5) : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: enabled ? color : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

class _TriggerModeButton extends StatelessWidget {
  final TriggerMode mode;
  final ValueChanged<TriggerMode> onChanged;

  const _TriggerModeButton({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TriggerMode>(
      segments: const [
        ButtonSegment(
            value: TriggerMode.auto,
            label: Text('Авто', style: TextStyle(fontSize: 11))),
        ButtonSegment(
            value: TriggerMode.normal,
            label: Text('Норм', style: TextStyle(fontSize: 11))),
        ButtonSegment(
            value: TriggerMode.single,
            label: Text('Одн.', style: TextStyle(fontSize: 11))),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
      ),
    );
  }
}

class _OscChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _OscChip(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ),
    );
  }
}
