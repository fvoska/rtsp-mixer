abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Nightwatch corner scale. Cards are deliberately soft (20) so a wall of them
/// reads calm at 3am; surfaces nested *inside* a card round less (12) so the
/// two radii don't fight, and small controls round least (8).
abstract final class Radii {
  static const double card = 20;
  static const double inner = 12;
  static const double control = 8;
}

/// Minimum comfortable tap target. Material's own guidance is 48dp; the card's
/// action row used to sit at 36 and was genuinely hard to hit half-asleep.
abstract final class Touch {
  static const double target = 48;
}
