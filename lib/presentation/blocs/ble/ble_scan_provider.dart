import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/hal/ble_hal.dart';

// ═══════════════════════════════════════════════════════════════
//  BLE Scanner Provider
//
//  Управляет сканированием BLE-устройств и хранит найденные
//  мультидатчики. Используется UI для выбора устройства.
// ═══════════════════════════════════════════════════════════════

/// Состояние BLE-сканера
class BleScanState {
  final bool isScanning;
  final List<BleDeviceResult> devices;
  final String? error;
  final bool isBluetoothOn;

  const BleScanState({
    this.isScanning = false,
    this.devices = const [],
    this.error,
    this.isBluetoothOn = false,
  });

  BleScanState copyWith({
    bool? isScanning,
    List<BleDeviceResult>? devices,
    String? error,
    bool? isBluetoothOn,
  }) =>
      BleScanState(
        isScanning: isScanning ?? this.isScanning,
        devices: devices ?? this.devices,
        error: error,
        isBluetoothOn: isBluetoothOn ?? this.isBluetoothOn,
      );
}

class BleScanController extends StateNotifier<BleScanState> {
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  BleScanController() : super(const BleScanState()) {
    _listenAdapter();
  }

  /// Слушаем состояние Bluetooth-адаптера
  void _listenAdapter() {
    try {
      _adapterSub = FlutterBluePlus.adapterState.listen((adapterState) {
        final isOn = adapterState == BluetoothAdapterState.on;
        state = state.copyWith(isBluetoothOn: isOn);

        if (!isOn && state.isScanning) {
          stopScan();
        }
      });
    } catch (e) {
      // BLE не поддерживается на этой платформе (Windows desktop)
      debugPrint('BLE: Адаптер недоступен ($e)');
    }
  }

  /// Запустить сканирование BLE-устройств
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (state.isScanning) return;

    // Проверяем поддержку BLE
    try {
      if (!await FlutterBluePlus.isSupported) {
        state = state.copyWith(
          error: 'Bluetooth не поддерживается на этом устройстве',
        );
        return;
      }
    } catch (e) {
      debugPrint('BLE: Платформа не поддерживает BLE ($e)');
      state = state.copyWith(
        error: 'BLE недоступен на этой платформе',
        isScanning: false,
      );
      return;
    }

    // Очищаем предыдущие результаты
    state = state.copyWith(
      isScanning: true,
      devices: [],
      error: null,
    );

    debugPrint('BLE Scanner: Начинаю сканирование ($timeout)');

    final foundDevices = <String, BleDeviceResult>{};

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final result in results) {
          final name = result.device.platformName.isNotEmpty
              ? result.device.platformName
              : result.advertisementData.advName;

          if (name.isEmpty) continue;

          // Добавляем все устройства с именем (для удобства), но PhysicsLab первым
          final id = result.device.remoteId.str;
          foundDevices[id] = BleDeviceResult(
            device: result.device,
            name: name,
            rssi: result.rssi,
          );

          // Обновляем стейт — сортируем: PhysicsLab первым, потом по RSSI
          final sorted = foundDevices.values.toList()
            ..sort((a, b) {
              final aIsLab = a.name.contains(kBleDeviceName) ? 0 : 1;
              final bIsLab = b.name.contains(kBleDeviceName) ? 0 : 1;
              if (aIsLab != bIsLab) return aIsLab.compareTo(bIsLab);
              return b.rssi.compareTo(a.rssi); // сильнее сигнал — выше
            });

          state = state.copyWith(devices: sorted);
        }
      },
      onError: (e) {
        debugPrint('BLE Scanner: Ошибка: $e');
        state = state.copyWith(
          error: 'Ошибка сканирования: $e',
          isScanning: false,
        );
      },
    );

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('BLE Scanner: Ошибка запуска: $e');
      state = state.copyWith(
        error: 'Не удалось начать сканирование: $e',
        isScanning: false,
      );
      return;
    }

    // Сканирование завершилось по таймауту
    state = state.copyWith(isScanning: false);
    debugPrint('BLE Scanner: Завершено. Найдено: ${foundDevices.length}');
  }

  /// Остановить сканирование
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _scanSub?.cancel();
    _scanSub = null;
    state = state.copyWith(isScanning: false);
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _scanSub?.cancel();
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
    super.dispose();
  }
}

/// Глобальный провайдер BLE-сканера
final bleScanProvider =
    StateNotifierProvider<BleScanController, BleScanState>((ref) {
  return BleScanController();
});

/// Выбранное BLE-устройство для подключения
final selectedBleDeviceProvider =
    StateProvider<BluetoothDevice?>((ref) => null);
