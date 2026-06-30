/// A single coach onboarding question (mirrors TrainersHQ `onboarding_questions`).
/// `type` is one of: shortText · longText · number · singleChoice · multiChoice
/// · photo · document.
class OnboardingQuestion {
  final String id;
  final String question;
  final String type;
  final List<String> options;
  final bool required;
  final int order;

  const OnboardingQuestion({
    required this.id,
    required this.question,
    required this.type,
    this.options = const [],
    this.required = false,
    this.order = 0,
  });

  factory OnboardingQuestion.fromMap(Map<String, dynamic> m, String id) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return OnboardingQuestion(
      id: id,
      question: (m['question'] ?? '').toString(),
      type: (m['type'] ?? 'shortText').toString(),
      options: List<String>.from(m['options'] ?? const []),
      required: m['required'] == true,
      order: toInt(m['order']),
    );
  }

  bool get isLongText => type == 'longText';
  bool get isNumber => type == 'number';
  bool get isSingleChoice => type == 'singleChoice';
  bool get isMultiChoice => type == 'multiChoice';
  bool get isChoice => isSingleChoice || isMultiChoice;
  bool get isPhoto => type == 'photo';
  bool get isDocument => type == 'document';
  bool get isFile => isPhoto || isDocument;
}
