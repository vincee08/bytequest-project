class LearnerNotification {
  const LearnerNotification(
      {required this.id,
      required this.title,
      required this.message,
      required this.createdAt,
      required this.isRead,
      this.activityType,
      this.activityId,
      this.classId,
      this.classTitle});
  final String id, title, message;
  final DateTime createdAt;
  final bool isRead;
  final String? activityType, activityId, classId, classTitle;
  bool get hasActivity =>
      activityId != null &&
      const {'quiz', 'homework', 'technical'}.contains(activityType);
  factory LearnerNotification.fromJson(Map<String, dynamic> row) {
    final meta = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
    return LearnerNotification(
        id: row['id'] as String,
        title: row['title'] as String,
        message: row['message'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        isRead: row['is_read'] == true,
        activityType: meta['activity_type'] as String?,
        activityId: meta['activity_id'] as String?,
        classId: meta['class_id'] as String?,
        classTitle: meta['class_title'] as String?);
  }
}
