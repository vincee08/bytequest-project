/// Learner copy for the submission rule an instructor sets on a homework
/// assignment (what to submit). The server enforces the same rule.
abstract final class HomeworkRequirementsContent {
  static const title = 'What to submit';
  static const imagesHelp = 'Images only: JPG, PNG or WEBP. Up to 10 MB per image; 5 files.';
  static const addImage = 'Attach image';
  static const answerOnlyHint = 'Enter your completed answer.';
  static const answerWithFilesHint = 'Enter your written answer. Attach the required files below.';
  static const missingAnswer = 'Write your answer before submitting.';
  static const answerNotAccepted =
      'This homework accepts files only. Your written text will not be submitted.';
  static const notImage =
      'Remove the files that are not images. This homework accepts JPG, PNG or WEBP only.';
  static const missingAnswerOrFile = 'Write an answer or attach a file before submitting.';

  static String _files(int count, bool images) => images
      ? '$count ${count == 1 ? 'image' : 'images'} (JPG, PNG or WEBP)'
      : '$count ${count == 1 ? 'file' : 'files'}';

  /// The rule as one plain sentence.
  static String rule(String format, int requiredFiles, bool images) => switch (format) {
        'answer' => 'Submit a written answer. Files are not accepted for this homework.',
        'file' => 'Submit at least ${_files(requiredFiles, images)}. This homework accepts files only, no written answer.',
        'answer_and_file' => 'Submit a written answer and at least ${_files(requiredFiles, images)}.',
        _ => images
            ? 'Submit a written answer, images (JPG, PNG or WEBP), or both.'
            : 'Submit a written answer, a file, or both.',
      };

  static String missingFiles(int remaining, bool images) =>
      'Attach ${_files(remaining, images)} more before submitting.';
}
