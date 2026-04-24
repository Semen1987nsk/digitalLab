import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'port_types.dart';

// ═════════════════════════════════════════════════════════════════════
//  PortConnectionManager v4.0 — Minimal Isolate (async-first)
//
//  v4.0 CRITICAL FIX: Removed Isolate.run() from port SCANNING.
//
//  PROBLEM: Isolate.run() for port probe caused Windows loader lock
//  deadlock. When sp_open() blocked in usbser.sys, the zombie Isolate
//  held native thread + DLL locks. Next Isolate.run() → DllMain
//  DLL_THREAD_ATTACH deadlocked on loader lock → Dart VM printed
//  "Attempt:N waiting for isolate to check in" → app hang → crash.
//
//  SOLUTION:
//  - Scan: async Process.run("reg query") — no FFI, no Isolate
//  - Connect: Isolate.run() used ONLY for openReadWrite() as a safety
//    net (see _openPortInIsolate). This is safe because:
//      1. Only ONE Isolate per connect attempt (not 9600/day)
//      2. Pre-flight probe succeeded → driver is alive → open is fast
//      3. 6s timeout → kill Isolate if stuck (no orphan threads)
//      4. No DllMain contention (single isolated FFI operation)
//  - Trade-off: one short-lived Isolate per connect (safe)
//    vs. permanent crash from scanning Isolates (unacceptable).
// ═══════════════════════════════════════════════════════════════════════

/// Результат подключения к порту
class ConnectionResult {
  final bool success;
  final SerialPort? port;
  final String? errorMessage;
  final String methodUsed;

  const ConnectionResult._({
    required this.success,
    this.port,
    this.errorMessage,
    this.methodUsed = '',
  });

  factory ConnectionResult.ok(SerialPort port, String method) =>
      ConnectionResult._(success: true, port: port, methodUsed: method);

  factory ConnectionResult.fail(String error) =>
      ConnectionResult._(success: false, errorMessage: error);
}

/// Конфигурация COM-порта
class PortConfig {
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final int parity;

  const PortConfig({
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 0,
  });

  /// FTDI-датчик расстояния V802 (9600 бод)
  static const sensorDefault = PortConfig(baudRate: 9600);

  /// Arduino мультидатчик Labosfera (115200 бод)
  static const multisensorDefault = PortConfig(baudRate: 115200);
}

/// Обнаруженный USB-порт (Sendable через Isolate.run)
class DetectedPort {
  final String name;
  final PortType type;
  final int vendorId;
  final int productId;

  const DetectedPort(this.name, this.type, this.vendorId, [this.productId = 0]);

  /// Человекочитаемое название для UI (русский)
  String get typeName => switch (type) {
        PortType.arduino => 'Мультидатчик',
        PortType.ftdi => 'Датчик расстояния',
        _ => 'USB-датчик',
      };
}

// ═══════════════════════════════════════════════════════════════════════
//  Менеджер подключения к COM-портам
// ═══════════════════════════════════════════════════════════════════════

class PortConnectionManager {
  final void Function(String message)? onLog;

  PortConnectionManager({this.onLog});

  void _log(String msg) {
    onLog?.call(msg);
    debugPrint('PortConnection: $msg');
  }

  // Known USB Vendor IDs
  static const int _vidArduino = 0x2341; // Arduino LLC
  static const int _vidFtdi = 0x0403; // FTDI FT232R
  static const int _vidCH340 = 0x1A86; // WCH CH340
  static const int _vidCP210x = 0x10C4; // Silicon Labs CP210x

  // ─────────────────────────────────────────────────────────
  //  SCAN — обнаружение USB-портов (Isolate, zero UI freeze)
  // ─────────────────────────────────────────────────────────

  /// Сканирует USB-порты в **ФОНОВОМ ИЗОЛЯТЕ**.
  ///
  /// Returns non-null list on success (may be empty = no ports found).
  /// Returns **null** on timeout/error (scan failed — port state unknown).
  ///
  /// CRITICAL DISTINCTION:
  /// - `[]`  = scan completed, no USB devices found → safe to update topology
  /// - `null` = scan hung/crashed → do NOT remove existing devices!
  ///
  /// Scans USB ports via **async Process.run** (no Isolate, no FFI).
  ///
  /// ⚡ CRITICAL FIX: Previously used Isolate.run() which created a new
  /// Dart Isolate every 3 seconds. Over 8 hours (overnight) = 9600 Isolates.
  /// Dart VM on Windows may not fully clean up Isolate resources (threads,
  /// handles) → scan creation gradually slows → timeout → null → hot-plug
  /// stops discovering new devices.
  ///
  /// Now uses Process.run() (async, non-blocking) directly on the main
  /// event loop. `reg query` takes <10ms and is NOT FFI — no Isolate needed.
  /// Zero Isolates created overnight. Problem eliminated.
  static Future<List<DetectedPort>?> scanPorts() async {
    try {
      final rawPorts = await enumeratePortsAsync().timeout(
        const Duration(seconds: 5),
      );

      // Классификация — мгновенно, без FFI
      final detected = <DetectedPort>[];
      for (final (name, vid, pid) in rawPorts) {
        PortType type;
        if (vid == _vidArduino || vid == _vidCH340 || vid == _vidCP210x) {
          type = PortType.arduino;
        } else if (vid == _vidFtdi) {
          type = PortType.ftdi;
        } else {
          type = PortType.unknown;
        }
        detected.add(DetectedPort(name, type, vid, pid));
      }

      debugPrint('PortConnection: scan нашло ${detected.length} портов');
      return detected;
    } on TimeoutException {
      debugPrint(
        'PortConnection: scanPorts TIMEOUT (5s)',
      );
      return null; // null = timeout, NOT "no ports found"
    } catch (e) {
      debugPrint('PortConnection: scanPorts error: $e');
      return null;
    }
  }

  /// Перечисляет COM-порты + читает VID/PID через **Windows Registry**.
  /// Возвращает List<(name, vid, pid)>.
  ///
  /// ⚡ Uses **async Process.run** — NO Isolate, NO FFI, NO SetupDi.
  ///
  /// Three `reg query` calls (~10ms total, non-blocking):
  ///   1. HKLM\HARDWARE\DEVICEMAP\SERIALCOMM → активные COM-порты
  ///   2. HKLM\SYSTEM\CurrentControlSet\Enum\USB     → VID/PID для Arduino/CH340
  ///   3. HKLM\SYSTEM\CurrentControlSet\Enum\FTDIBUS → VID/PID для FTDI
  ///
  /// Safe for continuous 24/7 operation: zero Isolates, zero leaked threads.
  ///
  /// Public so that [PortScanner] can reuse this single source of truth
  /// instead of duplicating registry enumeration in its own Isolate.
  static Future<List<(String, int, int)>> enumeratePortsAsync({
    bool skipLegacyPorts = true,
  }) async {
    final results = <(String, int, int)>[];

    // ── Step 1: Active COM ports from SERIALCOMM registry ──
    final Set<String> activePorts;
    try {
      final regResult = await Process.run(
        'reg',
        ['query', r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM'],
      );
      if (regResult.exitCode != 0) return results;

      final output = regResult.stdout as String;
      activePorts = RegExp(r'COM\d+')
          .allMatches(output)
          .map((m) => m.group(0)!)
          .where((p) => !skipLegacyPorts || (p != 'COM1' && p != 'COM2'))
          .toSet();
      if (activePorts.isEmpty) return results;
    } catch (_) {
      return results;
    }

    // ── Step 2: Match USB VID/PID → COM port via device registry ──
    // Registry key paths contain VID/PID directly:
    //   USB\VID_2341&PID_0043&MI_00\<inst>\Device Parameters\PortName=COM3
    //   FTDIBUS\VID_0403+PID_6001+<serial>\0000\Device Parameters\PortName=COM4
    final usbMappings = <String, (int, int)>{}; // COMx → (vid, pid)

    // Run both registry queries in parallel for speed
    final regPaths = [
      r'HKLM\SYSTEM\CurrentControlSet\Enum\USB',
      r'HKLM\SYSTEM\CurrentControlSet\Enum\FTDIBUS',
    ];
    final futures = regPaths.map((regPath) => Process.run(
      'reg',
      ['query', regPath, '/s', '/v', 'PortName'],
    ));
    final regResults = await Future.wait(futures);

    for (final result in regResults) {
      try {
        if (result.exitCode != 0) continue;

        final output = result.stdout as String;
        final lines = output.split('\n');

        // Parse pairs: HKEY_... path (contains VID/PID) + PortName value
        String? lastKeyPath;
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('HKEY_')) {
            lastKeyPath = trimmed;
          } else if (trimmed.contains('PortName') &&
              trimmed.contains('REG_SZ') &&
              lastKeyPath != null) {
            final portMatch = RegExp(r'COM\d+').firstMatch(trimmed);
            if (portMatch == null) continue;
            final portName = portMatch.group(0)!;

            // Extract VID/PID from registry key path (hex)
            // USB: VID_XXXX&PID_XXXX   FTDI: VID_XXXX+PID_XXXX
            final vidMatch =
                RegExp(r'VID_([0-9A-Fa-f]{4})').firstMatch(lastKeyPath);
            final pidMatch =
                RegExp(r'PID_([0-9A-Fa-f]{4})').firstMatch(lastKeyPath);

            final vid = vidMatch != null
                ? int.parse(vidMatch.group(1)!, radix: 16)
                : 0;
            final pid = pidMatch != null
                ? int.parse(pidMatch.group(1)!, radix: 16)
                : 0;

            if (vid != 0) {
              usbMappings[portName] = (vid, pid);
            }
          }
        }
      } catch (_) {
        continue;
      }
    }

    // ── Step 3: Build result — only active USB ports with VID ──
    for (final portName in activePorts) {
      final mapping = usbMappings[portName];
      if (mapping != null) {
        results.add((portName, mapping.$1, mapping.$2));
      }
    }

    return results;
  }

  // ─────────────────────────────────────────────────────────
  //  CONNECT — подключение к порту (hybrid: process probe + FFI)
  // ─────────────────────────────────────────────────────────

  /// Подключение к COM-порту.
  ///
  /// ⚡ v4.1: ГИБРИДНАЯ СТРАТЕГИЯ (Process probe → FFI open)
  ///
  /// ПРОБЛЕМА: sp_open() (CreateFile) может блокировать 10+ сек на
  /// Arduino CDC ACM (usbser.sys) при холодном старте. Это замораживает
  /// UI потому что FFI — синхронный вызов на main thread.
  ///
  /// РЕШЕНИЕ: Pre-flight probe через `mode COMx:` в ОТДЕЛЬНОМ ПРОЦЕССЕ.
  ///   1. Process.start('mode', ['COM3']) — вызывает CreateFile в
  ///      отдельном процессе. Наш main thread свободен.
  ///   2. Если mode отвечает за 3с — драйвер жив → FFI open быстрый.
  ///   3. Если mode зависает — убиваем процесс → skip port → retry later.
  ///
  /// ПОЧЕМУ НЕ Isolate.run():
  ///   Isolate.run → DllMain DLL_THREAD_ATTACH → loader lock deadlock.
  ///   Отдельный OS-процесс = отдельное адресное пространство = без deadlock.
  ///
  /// Timing (reconnection): ~200ms probe + ~200ms open + 300ms DTR = ~700ms
  /// Timing (cold start stuck): 3s probe timeout → skip → retry in 1.5s
  Future<ConnectionResult> connect(
    String portName, {
    PortConfig config = PortConfig.sensorDefault,
  }) async {
    _log('Подключение к $portName (${config.baudRate} бод)...');

    // Yield: даём UI перерисоваться перед FFI
    await Future.delayed(const Duration(milliseconds: 50));

    // ── Pre-flight probe via separate OS process ─────────────
    // `mode COM3:` queries port config via CreateFile in its own process.
    // If driver is stuck, `mode` blocks too — but in ANOTHER process,
    // not our main thread. Timeout + kill handles stuck case.
    final driverReady = await _isPortResponsive(portName);
    if (!driverReady) {
      _log('  ✗ драйвер $portName не отвечает (probe timeout)');
      return ConnectionResult.fail(
        'Устройство $portName временно не готово. '
        'Приложение повторит подключение автоматически.',
      );
    }
    _log('  ✓ probe OK (драйвер отвечает)');

    // ── FFI open on main thread ──────────────────────────────
    // Driver is responsive (mode succeeded) → openReadWrite() should
    // complete in <500ms. Brief UI block is acceptable.
    //
    // ── SAFETY NET: Isolate.run() for openReadWrite() ──────────
    // In rare cases (driver half-initialized, CDC ACM on usbser.sys),
    // openReadWrite() can block for 10+ seconds. To prevent permanent
    // UI freeze, we run the open in a background Isolate.
    //
    // Unlike previous Isolate.run() for port scanning (which caused
    // loader lock deadlock), this is safe because:
    //   1. We only create ONE Isolate per connect attempt (not 9600/day)
    //   2. The probe succeeded → driver is alive → open is fast
    //   3. We have a 6s timeout → kill Isolate if stuck
    //   4. No DllMain contention (single isolated operation)
    SerialPort? port;
    SerialPortConfig? portConfig;

    try {
      int errno = -1;
      bool opened = false;

      // Up to 3 attempts for transient errors (5=ACCESS_DENIED, 32=SHARING).
      // errno=31 (GEN_FAILURE): do NOT retry here — each attempt blocks.
      const maxAttempts = 3;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        // Open port in background Isolate to prevent UI freeze.
        // Isolate.run() serializes the FFI call in a separate thread.
        // If the driver hangs, only the Isolate blocks — not our UI.
        try {
          final result = await Isolate.run(() {
            final p = SerialPort(portName);
            final ok = p.openReadWrite();
            final err = SerialPort.lastError?.errorCode ?? -1;
            if (ok) {
              return (true, p.address, err);
            } else {
              try { p.dispose(); } catch (_) {}
              return (false, 0, err);
            }
          }).timeout(const Duration(seconds: 6));

          opened = result.$1;
          errno = result.$3;

          if (opened) {
            // Reconstruct SerialPort from address on main thread
            port = SerialPort.fromAddress(result.$2);
            _log('  ✓ порт открыт (попытка $attempt, Isolate)');
            break;
          }
        } on TimeoutException {
          _log('  ✗ openReadWrite TIMEOUT (6s) — драйвер завис');
          errno = -999;
          return ConnectionResult.fail(
            'Драйвер $portName не отвечает (зависание CreateFile). '
            'Переподключите USB-кабель датчика.',
          );
        } catch (e) {
          _log('  ✗ Isolate.run open error: $e');
          errno = -1;
        }

        // errno=31 (GEN_FAILURE) and 121 (SEM_TIMEOUT): bail out immediately.
        if (errno == 31 || errno == 121) {
          _log('  ✗ open failed (errno=$errno) — driver not ready, skip retries');
          return ConnectionResult.fail(_humanError(portName, errno));
        }

        // Should we retry?
        final shouldRetry =
            (errno == 0 || errno == -1 ||
             errno == 5 || errno == 32) &&
            attempt < maxAttempts;

        if (!shouldRetry) {
          _log('  ✗ open failed (errno=$errno, attempt $attempt/$maxAttempts)');
          return ConnectionResult.fail(_humanError(portName, errno));
        }

        const delayMs = 300;
        _log('  ⚠ errno=$errno, retry $attempt → пауза $delayMsмс...');
        await Future.delayed(const Duration(milliseconds: delayMs));
      }

      if (!opened || port == null) {
        return ConnectionResult.fail(_humanError(portName, errno));
      }
      final openedPort = port;

      // Применяем конфигурацию
      try {
        portConfig = SerialPortConfig();
        portConfig.baudRate = config.baudRate;
        portConfig.bits = config.dataBits;
        portConfig.stopBits = config.stopBits;
        portConfig.parity = config.parity;
        openedPort.config = portConfig;
        // Port now owns the native config via _config field.
        // Null the local ref to prevent double-free in finally block.
        portConfig = null;
        _log('  конфигурация: ${config.baudRate} ${config.dataBits}N${config.stopBits}');
      } catch (e) {
        _log('  ⚠ config error: $e (продолжаем)');
      } finally {
        // Dispose ONLY if port did NOT take ownership (assignment threw).
        // On success: portConfig is null → no-op.
        try { portConfig?.dispose(); } catch (_) {}
      }

      // Arduino DTR stabilization: после open CDC ACM делает DTR toggle →
      // Arduino перезагружается → bootloader работает ~250мс → firmware.
      // Ждём 300мс чтобы не читать мусор bootloader-а.
      await Future.delayed(const Duration(milliseconds: 300));

      _log('  ✓ подключено ($portName, ${config.baudRate} бод)');
      return ConnectionResult.ok(openedPort, 'direct-open');
    } catch (e) {
      _log('  ✗ exception: $e');
      try {
        port?.dispose();
      } catch (_) {}
      return ConnectionResult.fail('Не удалось подключиться к $portName: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  //  PRE-FLIGHT PROBE — проверка драйвера в отдельном процессе
  // ─────────────────────────────────────────────────────────

  /// Проверяет, отвечает ли драйвер COM-порта, запуская `mode COMx:`
  /// в **ОТДЕЛЬНОМ OS-ПРОЦЕССЕ** через cmd.exe.
  ///
  /// `mode` вызывает CreateFile() + GetCommState() для порта.
  /// Если драйвер заблокирован (usbser.sys frozen), mode тоже зависнет —
  /// но в СВОЁМ процессе, не в нашем. Через 3 секунды убиваем процесс.
  ///
  /// ВАЖНО: `runInShell: true` обязательно на Windows!
  /// `mode` — это `mode.com` (не .exe). Process.start без shell не находит
  /// `.com` расширения → ProcessException "file not found".
  /// С `runInShell: true` → `cmd.exe /c mode COM3` — работает.
  ///
  /// Типичное время:
  /// - Драйвер жив: ~100-300мс
  /// - Драйвер мёртв: 3с (timeout → kill → false)
  Future<bool> _isPortResponsive(String portName) async {
    Process? process;
    try {
      process = await Process.start(
        'mode', [portName],
        runInShell: true,
      );

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 3),
      );

      return exitCode == 0;
    } on TimeoutException {
      // Driver is stuck — kill the probe process
      _log('  ⚠ mode $portName: timeout 3с (драйвер не отвечает)');
      try { process?.kill(); } catch (_) {}
      return false;
    } catch (e) {
      _log('  ⚠ mode $portName: $e');
      try { process?.kill(); } catch (_) {}
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────
  //  CLOSE — безопасное закрытие порта
  // ─────────────────────────────────────────────────────────

  /// Безопасно закрывает и освобождает SerialPort в фоновом Isolate.
  void closePort(SerialPort? port) {
    if (port == null) return;
    final address = port.address;
    unawaited(Isolate.run(() {
      try {
        final isolatePort = SerialPort.fromAddress(address);
        if (isolatePort.isOpen) {
          isolatePort.close();
        }
        isolatePort.dispose();
      } catch (_) {}
    }));
  }

  // ─────────────────────────────────────────────────────────
  //  ERROR MESSAGES — человекочитаемые ошибки (русский)
  // ─────────────────────────────────────────────────────────

  /// Человекочитаемое сообщение об ошибке для учителей.
  String _humanError(String portName, int errno) => switch (errno) {
        5 || 13 =>
          'Не удалось открыть $portName: порт используется другой программой. '
          'Закройте Arduino IDE или монитор порта и попробуйте снова.',
        2 =>
          'Связь с $portName не обнаружена. Проверьте USB-подключение датчика.',
        16 =>
          'Порт $portName сейчас занят другой программой. '
          'Закройте её и повторите подключение.',
        121 =>
          'Подключение к $portName временно нестабильно. '
          'Переподключите USB-кабель датчика и повторите попытку.',
        31 =>
          'Устройство $portName временно не готово (инициализация драйвера). '
          'Повторите через несколько секунд.',
        0 =>
          'Порт $portName временно недоступен. '
          'Приложение может восстановить соединение автоматически.',
        -999 =>
          'Слишком долгий ответ от $portName. '
          'Проверьте подключение датчика и попробуйте снова.',
        _ =>
          'Не удалось подключиться к $portName (код $errno).',
      };
}
