class Study {
  const Study({required this.id, required this.name});

  final int id;
  final String name;

  factory Study.fromJson(Map<String, dynamic> json) => Study(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
      );
}
