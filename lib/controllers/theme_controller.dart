import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends GetxController {
  static const _key = 'isDarkMode';

  final RxBool isDarkMode = false.obs;

  // ---------------------------------------------------------------------------
  @override
  void onInit() {
    super.onInit();
    _loadTheme();
  }

  // ---------------------------------------------------------------------------
  void toggleTheme() {
    isDarkMode.value = !isDarkMode.value;
    _applyAndSave();
  }

  void setDark() {
    isDarkMode.value = true;
    _applyAndSave();
  }

  void setLight() {
    isDarkMode.value = false;
    _applyAndSave();
  }

  // ---------------------------------------------------------------------------
  void _applyAndSave() {
    Get.changeThemeMode(isDarkMode.value ? ThemeMode.dark : ThemeMode.light);
    _saveTheme(isDarkMode.value);
  }

  // ---------------------------------------------------------------------------
  Future<void> _saveTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, isDark);
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getBool(_key) ?? false;

    isDarkMode.value = savedTheme;

    Get.changeThemeMode(savedTheme ? ThemeMode.dark : ThemeMode.light);
  }
}
