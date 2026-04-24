import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/app_database.dart';
import '../../data/datasources/local/experiment_autosave_service.dart';

// ═══════════════════════════════════════════════════════════════
//  ГЛОБАЛЬНЫЕ ПРОВАЙДЕРЫ БАЗЫ ДАННЫХ
// ═══════════════════════════════════════════════════════════════

/// Singleton AppDatabase — живёт всё время работы приложения.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Autosave-сервис — привязан к AppDatabase.
final autosaveServiceProvider = Provider<ExperimentAutosaveService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final service = ExperimentAutosaveService(db);
  ref.onDispose(() => service.dispose());
  return service;
});
