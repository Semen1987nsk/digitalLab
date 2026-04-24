import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'port_connection_manager.dart';
import 'port_types.dart';

// Re-export types so existing `import 'port_scanner.dart'` still works.
export 'port_types.dart';

/// Сканер COM-портов с проверкой доступности
class PortScanner {
  /// Callback для логирования
  final void Function(String message)? onLog;
  
  PortScanner({this.onLog});
  
  void _log(String message) {
    onLog?.call(message);
    debugPrint('PortScanner: $message');
  }
  
  /// Очищает строку от невалидных UTF-8 символов (проблема кодировки Windows)
  String _sanitizeString(String input) {
    if (input.isEmpty) return input;
    
    // Проверяем на типичные признаки неправильной кодировки
    // CP1251 "Последовательный порт" читается как "Ïîñëåäîâàòåëüíûé ïîðò"
    // Символы Ï, î, ñ и т.д. - это 0xCF, 0xEE, 0xF1 в UTF-8
    
    // Если есть символы из диапазона кириллицы CP1251, 
    // но они не образуют валидную UTF-8 последовательность
    bool hasEncodingIssue = false;
    
    for (int i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      // Эти символы часто появляются при неправильной кодировке
      // Ï = 0xCF (207), î = 0xEE (238), ñ = 0xF1 (241), etc.
      if ((c >= 0xC0 && c <= 0xFF) && i + 1 < input.length) {
        final next = input.codeUnitAt(i + 1);
        // В правильной UTF-8 за байтом 0xC0-0xDF должен идти 0x80-0xBF
        // Но в испорченной кодировке идут другие символы
        if (c >= 0xC0 && c <= 0xDF && (next < 0x80 || next > 0xBF)) {
          hasEncodingIssue = true;
          break;
        }
      }
      // Простая проверка: если много символов > 127 подряд - скорее всего проблема
      if (c > 127 && c < 256) {
        hasEncodingIssue = true;
        break;
      }
    }
    
    if (hasEncodingIssue) {
      return ''; // Не показываем мусор
    }
    
    // Удаляем непечатаемые символы
    return input.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  }
  
  /// Сканирует все порты и возвращает полную информацию.
  ///
  /// ⚡ v2.0: Делегирует перечисление портов в
  /// [PortConnectionManager.enumeratePortsAsync] — единый источник истины.
  /// Ранее дублировал ту же логику через Isolate.run + Process.runSync,
  /// что создавало риск расхождения и loader lock deadlock.
  ///
  /// Availability probe (openRead) по-прежнему выполняется в Isolate.run(),
  /// но это **одноразовая** операция (не 9600/день), поэтому безопасно.
  Future<List<PortInfo>> scanPorts({
    bool testAvailability = true,
    void Function(String message)? onProgress,
  }) async {
    void log(String message) {
      _log(message);
      onProgress?.call(message);
    }

    log('Начало сканирования портов...');

    try {
      // ── Step 1: Enumerate ports via shared async registry scanner ──
      final rawPorts = await PortConnectionManager.enumeratePortsAsync(
        skipLegacyPorts: false, // PortScanner shows ALL ports including COM1/COM2
      ).timeout(const Duration(seconds: 8));

      // ── Step 2: Probe availability in background Isolate (FFI) ──
      // openRead() is sync FFI (CreateFile) — must not run on main thread.
      // Single Isolate.run() for all ports at once (not per-port).
      final Map<String, (int, String?)> availabilityMap;
      if (testAvailability && rawPorts.isNotEmpty) {
        final portNames = rawPorts.map((r) => r.$1).toList();
        availabilityMap = await Isolate.run(
          () => _probeAvailabilitySync(portNames),
        ).timeout(const Duration(seconds: 6));
      } else {
        availabilityMap = {};
      }

      // ── Step 3: Build PortInfo list on main thread (no FFI) ──
      final result = <PortInfo>[];
      for (final (name, vid, pid) in rawPorts) {
        // Derive description/manufacturer from known VIDs
        String description = '';
        String manufacturer = '';
        if (vid == 0x0403) {
          description = 'USB Serial Port (FTDI)';
          manufacturer = 'FTDI';
        } else if (vid == 0x2341) {
          description = 'Arduino USB Serial';
          manufacturer = 'Arduino LLC';
        } else if (vid == 0x1A86) {
          description = 'USB-Serial CH340';
          manufacturer = 'WCH';
        } else if (vid == 0x10C4) {
          description = 'USB Serial CP210x';
          manufacturer = 'Silicon Labs';
        } else if (name == 'COM1' || name == 'COM2') {
          description = 'Built-in Serial Port';
        }

        final type = _detectPortType(name, description, manufacturer, vid);

        final probe = availabilityMap[name];
        final availability = probe != null
            ? PortAvailability.values[probe.$1]
            : PortAvailability.untested;
        final error = probe?.$2;

        final portInfo = PortInfo(
          name: name,
          description: _sanitizeString(description),
          manufacturer: _sanitizeString(manufacturer),
          type: type,
          availability: availability,
          errorMessage: error,
          vendorId: vid == 0 ? null : vid,
          productId: pid == 0 ? null : pid,
        );

        result.add(portInfo);
        log('  $portInfo');
      }

      // Сортируем: наши датчики первые, затем доступные
      result.sort((a, b) {
        if (a.isLikelyOurSensor && !b.isLikelyOurSensor) return -1;
        if (!a.isLikelyOurSensor && b.isLikelyOurSensor) return 1;
        if (a.canConnect && !b.canConnect) return -1;
        if (!a.canConnect && b.canConnect) return 1;
        return a.name.compareTo(b.name);
      });

      log('Сканирование завершено: ${result.length} портов');
      return result;
    } on TimeoutException {
      log('Сканирование TIMEOUT (8s) — драйвер не отвечает');
      return [];
    } catch (e) {
      log('Ошибка сканирования: $e');
      return [];
    }
  }

  /// Проверяет доступность портов через openRead() в **ФОНОВОМ ИЗОЛЯТЕ**.
  ///
  /// Выполняется ОДИН РАЗ за сканирование (не per-port).
  /// Возвращает Map<portName, (availabilityIndex, errorMessage?)>.
  static Map<String, (int, String?)> _probeAvailabilitySync(
    List<String> portNames,
  ) {
    final results = <String, (int, String?)>{};

    for (final name in portNames) {
      try {
        final probePort = SerialPort(name);
        final opened = probePort.openRead();
        if (opened) {
          results[name] = (PortAvailability.available.index, null);
          try { probePort.close(); } catch (_) {}
        } else {
          final code = SerialPort.lastError?.errorCode ?? -1;
          if (code == 5 || code == 13) {
            results[name] = (PortAvailability.accessDenied.index, null);
          } else if (code == 16) {
            results[name] = (PortAvailability.busy.index, null);
          } else {
            results[name] = (PortAvailability.error.index, null);
          }
        }
        try { probePort.dispose(); } catch (_) {}
      } catch (e) {
        results[name] = (PortAvailability.error.index, e.toString());
      }
    }

    return results;
  }
  
  /// Определяет тип порта по его характеристикам
  PortType _detectPortType(String name, String description, String manufacturer, int? vendorId) {
    final descLower = description.toLowerCase();
    final mfrLower = manufacturer.toLowerCase();
    
    // FTDI (VID: 0x0403)
    if (vendorId == 0x0403 ||
        descLower.contains('ftdi') ||
        descLower.contains('ft232') ||
        mfrLower.contains('ftdi')) {
      return PortType.ftdi;
    }
    
    // Arduino UNO/Mega (VID: 0x2341 — Arduino LLC)
    // Также CH340, CP210x (клоны)
    if (vendorId == 0x2341 ||
        descLower.contains('ch340') ||
        descLower.contains('cp210') ||
        descLower.contains('arduino') ||
        mfrLower.contains('arduino') ||
        mfrLower.contains('wch') ||
        mfrLower.contains('silicon labs')) {
      return PortType.arduino;
    }
    
    // CDC ACM / USB Serial (может быть Arduino UNO через usbser.sys)
    // Только если VID указывает на Arduino-совместимое устройство
    if (vendorId == 0x2341 || vendorId == 0x1A86 || vendorId == 0x10C4) {
      return PortType.arduino;
    }
    
    // FTDI по VID (если описание не помогло)
    if (vendorId == 0x0403) {
      return PortType.ftdi;
    }
    
    // Неизвестный USB — НЕ считаем автоматически датчиком
    if (descLower.contains('usb serial') ||
        descLower.contains('usb-serial') ||
        (descLower.isEmpty && vendorId != null && vendorId > 0)) {
      return PortType.unknown;
    }
    
    // Bluetooth
    if (descLower.contains('bluetooth') ||
        descLower.contains('bth') ||
        descLower.contains('rfcomm')) {
      return PortType.bluetooth;
    }
    
    // USB Serial - НЕ считаем автоматически датчиком!
    // SUNIX и другие PCI-E карты тоже показываются как USB Serial
    // Только FTDI VID 0x0403 гарантированно наш датчик
    // if (descLower.contains('usb') && descLower.contains('serial')) {
    //   return PortType.ftdi; // УДАЛЕНО - это неправильно
    // }
    
    // Встроенные порты (COM1, COM2 часто)
    if (name == 'COM1' || name == 'COM2') {
      // Но проверяем - может быть USB
      if (descLower.contains('usb')) {
        return PortType.unknown;
      }
      return PortType.builtin;
    }
    
    // Виртуальные порты
    if (descLower.contains('virtual') ||
        descLower.contains('emulated')) {
      return PortType.virtual;
    }
    
    return PortType.unknown;
  }
  
  /// Находит лучший порт для датчика (автовыбор)
  /// Приоритет: Arduino мультидатчик > FTDI датчик расстояния
  PortInfo? findBestSensorPort(List<PortInfo> ports) {
    // 1. Ищем Arduino мультидатчик (приоритет — больше датчиков)
    for (final port in ports) {
      if (port.isArduinoMultisensor && port.canConnect) {
        _log('Лучший порт (Arduino мультидатчик): ${port.name}');
        return port;
      }
    }
    
    // 2. Ищем FTDI датчик расстояния
    for (final port in ports) {
      if (port.isFtdiDistanceSensor && port.canConnect) {
        _log('Лучший порт (FTDI расстояние): ${port.name}');
        return port;
      }
    }
    
    // 3. Ищем любой наш порт (даже недоступный - для диагностики)
    for (final port in ports) {
      if (port.isLikelyOurSensor) {
        _log('Датчик найден но недоступен: ${port.name} - ${port.availabilityDescription}');
        return port;
      }
    }
    
    // Ничего не найдено
    _log('Датчик не найден. Подключите мультидатчик к USB.');
    return null;
  }
}
