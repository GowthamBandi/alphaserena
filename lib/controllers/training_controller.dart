import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';

/// Loads the member's assigned workout + diet content from the getMyTraining
/// Cloud Function (resolved server-side; no direct reads of gym collections).
class TrainingController extends GetxController {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  final RxBool isLoading = true.obs;
  final RxString error = ''.obs;
  final Rxn<Map<String, dynamic>> workout = Rxn<Map<String, dynamic>>();
  final Rxn<Map<String, dynamic>> diet = Rxn<Map<String, dynamic>>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    try {
      isLoading.value = true;
      error.value = '';
      final res = await _functions.httpsCallable('getMyTraining').call();
      final data = Map<String, dynamic>.from(res.data as Map);
      workout.value = data['workout'] != null
          ? Map<String, dynamic>.from(data['workout'])
          : null;
      diet.value =
          data['diet'] != null ? Map<String, dynamic>.from(data['diet']) : null;
    } catch (_) {
      error.value = 'Could not load your training. Tap retry.';
    } finally {
      isLoading.value = false;
    }
  }

  List<Map<String, dynamic>> get workoutItems =>
      ((workout.value?['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get dietItems =>
      ((diet.value?['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
}
