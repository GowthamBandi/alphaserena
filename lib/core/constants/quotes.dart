/// Motivational lines for the "arena for alphas" brand. Surfaced on the splash,
/// home header, rest timer, and empty states.
class Quotes {
  Quotes._();

  static const List<String> all = [
    "Welcome to the arena. Alphas are forged here.",
    "Discipline is the bridge between goals and results.",
    "Sweat now, shine later.",
    "Every rep writes your legend.",
    "Rise. Grind. Conquer.",
    "The body achieves what the mind believes.",
    "Show up. Level up.",
    "Pain is temporary. Pride is forever.",
    "Champions train when no one is watching.",
    "Your only competition is who you were yesterday.",
    "Strong is the new standard.",
    "Fall seven times, stand up eight.",
    "Make your body the hardest thing to beat.",
    "Greatness is earned, never given.",
    "One more rep, one step closer.",
    "Enter the arena. Leave a legend.",
    "Hard work beats talent when talent doesn't work hard.",
    "Your future self is watching you right now.",
  ];

  /// Short hype lines for buttons / banners.
  static const List<String> hype = [
    "ENTER THE ARENA",
    "OWN TODAY",
    "EARN IT",
    "NO EXCUSES",
    "BUILT, NOT BORN",
  ];

  /// Stable quote for the whole day (won't change on rebuilds).
  static String daily() => all[DateTime.now().day % all.length];

  /// A fresh random quote each call.
  static String random() => (List<String>.of(all)..shuffle()).first;
}
