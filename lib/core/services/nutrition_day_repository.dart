/// NIP PHASE A — the persistence seam for the member's daily nutrition log.
///
/// [DietLogController] used to construct [DietLogService] directly, welding the
/// controller to the legacy `client_diet_logs` schema. This interface names
/// today's two operations — watch a day, persist the day's marks — so Phase B
/// can swap in a `client_nutrition_days` implementation without touching the
/// controller (or any screen). The LEGACY adapter below is the Phase A default
/// and is a pure pass-through: same service, same models, same
/// [DietSaveResult] contract, byte-identical behavior.
library;

import '../models/client_diet_log_model.dart';
import 'diet_log_service.dart';

export 'diet_log_service.dart' show DietSaveResult;

/// What the diet-adherence controller needs from persistence — nothing more.
abstract class NutritionDayRepository {
  /// The member is linked to a gym `clients` doc and may log.
  bool get canLog;

  /// Live stream of one day's log (null until the member marks something).
  Stream<ClientDietLogModel?> watchDay(String dateKey);

  /// Upserts the day's marks. Mirrors [DietLogService.saveDay] exactly,
  /// including the three-state [DietSaveResult] (queued is NOT a failure).
  Future<DietSaveResult> saveDay({
    required String dateKey,
    required String planName,
    required List<Map<String, dynamic>> items,
    required double adherencePct,
    bool markCreated = false,
  });
}

/// Phase A adapter: the existing `client_diet_logs` backend, unchanged.
class LegacyDietLogRepository implements NutritionDayRepository {
  final DietLogService _service;

  LegacyDietLogRepository({DietLogService? service})
      : _service = service ?? DietLogService();

  @override
  bool get canLog => _service.canLog;

  @override
  Stream<ClientDietLogModel?> watchDay(String dateKey) =>
      _service.watchDay(dateKey);

  @override
  Future<DietSaveResult> saveDay({
    required String dateKey,
    required String planName,
    required List<Map<String, dynamic>> items,
    required double adherencePct,
    bool markCreated = false,
  }) =>
      _service.saveDay(
        dateKey: dateKey,
        planName: planName,
        items: items,
        adherencePct: adherencePct,
        markCreated: markCreated,
      );
}
