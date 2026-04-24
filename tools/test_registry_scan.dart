// ignore_for_file: avoid_print
// Quick diagnostic: test registry-based COM port enumeration
// Run: dart run tools/test_registry_scan.dart

import 'dart:io';

void main() {
  print('=== Test: Registry-based COM port scan ===\n');

  // Step 1: Active COM ports
  print('Step 1: HKLM\\HARDWARE\\DEVICEMAP\\SERIALCOMM');
  final regResult = Process.runSync(
    'reg',
    ['query', r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM'],
  );
  print('  exit code: ${regResult.exitCode}');
  print('  stdout: ${regResult.stdout}');

  final activePorts = RegExp(r'COM\d+')
      .allMatches(regResult.stdout as String)
      .map((m) => m.group(0)!)
      .where((p) => p != 'COM1' && p != 'COM2')
      .toSet();
  print('  active USB ports: $activePorts\n');

  // Step 2: VID/PID from USB registry
  final usbMappings = <String, (int, int)>{};
  for (final regPath in [
    r'HKLM\SYSTEM\CurrentControlSet\Enum\USB',
    r'HKLM\SYSTEM\CurrentControlSet\Enum\FTDIBUS',
  ]) {
    print('Step 2: $regPath');
    final result = Process.runSync(
      'reg',
      ['query', regPath, '/s', '/v', 'PortName'],
    );
    print('  exit code: ${result.exitCode}');

    if (result.exitCode != 0) {
      print('  (skipped)\n');
      continue;
    }

    final output = result.stdout as String;
    final lines = output.split('\n');
    String? lastKey;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('HKEY_')) {
        lastKey = trimmed;
      } else if (trimmed.contains('PortName') &&
          trimmed.contains('REG_SZ') &&
          lastKey != null) {
        final portMatch = RegExp(r'COM\d+').firstMatch(trimmed);
        if (portMatch == null) continue;
        final portName = portMatch.group(0)!;

        final vidMatch =
            RegExp(r'VID_([0-9A-Fa-f]{4})').firstMatch(lastKey);
        final pidMatch =
            RegExp(r'PID_([0-9A-Fa-f]{4})').firstMatch(lastKey);
        final vid =
            vidMatch != null ? int.parse(vidMatch.group(1)!, radix: 16) : 0;
        final pid =
            pidMatch != null ? int.parse(pidMatch.group(1)!, radix: 16) : 0;

        if (vid != 0) {
          usbMappings[portName] = (vid, pid);
          print(
              '  FOUND: $portName → VID=0x${vid.toRadixString(16).padLeft(4, '0')} PID=0x${pid.toRadixString(16).padLeft(4, '0')}');
        }
      }
    }
    print('');
  }

  // Step 3: Final result
  print('=== RESULT ===');
  for (final portName in activePorts) {
    final mapping = usbMappings[portName];
    if (mapping != null) {
      final vid = mapping.$1;
      final pid = mapping.$2;
      String type;
      if (vid == 0x2341 || vid == 0x1A86 || vid == 0x10C4) {
        type = 'Arduino/Multisensor';
      } else if (vid == 0x0403) {
        type = 'FTDI/Distance';
      } else {
        type = 'Unknown';
      }
      print(
          '  $portName: $type (VID=0x${vid.toRadixString(16).padLeft(4, '0')} PID=0x${pid.toRadixString(16).padLeft(4, '0')})');
    } else {
      print('  $portName: no USB VID/PID mapping');
    }
  }
  print('\nDone! Time: ${DateTime.now()}');
}
