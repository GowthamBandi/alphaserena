class WorkoutModel {
  final String title;
  final String description;
  final String videoUrl;
  final List<WorkoutSet> sets;

  WorkoutModel({
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.sets,
  });

  factory WorkoutModel.fromJson(Map<String, dynamic> json) {
    return WorkoutModel(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      videoUrl: json['videoUrl'] ?? '',
      sets: (json['sets'] as List<dynamic>)
          .map((e) => WorkoutSet.fromJson(e))
          .toList(),
    );
  }
}

class WorkoutSet {
  final int set;
  final int reps;
  final double weight;

  WorkoutSet({required this.set, required this.reps, required this.weight});

  factory WorkoutSet.fromJson(Map<String, dynamic> json) {
    return WorkoutSet(
      set: json['set'] ?? 0,
      reps: json['reps'] ?? 0,
      weight: (json['weight'] ?? 0).toDouble(),
    );
  }
}
