import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/providers.dart';

class SettingsState {
  const SettingsState({
    required this.keepRecordingsLocally,
  });

  final bool keepRecordingsLocally;

  SettingsState copyWith({bool? keepRecordingsLocally}) {
    return SettingsState(
      keepRecordingsLocally: keepRecordingsLocally ?? this.keepRecordingsLocally,
    );
  }
}

final settingsControllerProvider = StateNotifierProvider<SettingsController, SettingsState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsController(prefs);
});

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this._preferences)
      : super(SettingsState(
          keepRecordingsLocally: _preferences.getBool(_keepRecordingsLocallyKey) ?? false,
        ));

  static const _keepRecordingsLocallyKey = 'keep_recordings_locally';

  final SharedPreferences _preferences;

  Future<void> setKeepRecordingsLocally(bool value) async {
    await _preferences.setBool(_keepRecordingsLocallyKey, value);
    state = state.copyWith(keepRecordingsLocally: value);
  }
}
