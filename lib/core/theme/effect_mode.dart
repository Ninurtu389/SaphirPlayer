enum EffectMode {
  glass,
  lean;

  static EffectMode fromStorage(String? rawValue) {
    if (rawValue == 'lean') {
      return EffectMode.lean;
    }
    return EffectMode.glass;
  }

  String toStorage() {
    switch (this) {
      case EffectMode.glass:
        return 'glass';
      case EffectMode.lean:
        return 'lean';
    }
  }
}
