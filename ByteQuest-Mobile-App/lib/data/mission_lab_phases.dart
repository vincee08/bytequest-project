import 'mission_content_data.dart';

/// Guidance for one step of a phase that a realistic lab owns.
final class MissionLabGuide {
  const MissionLabGuide(this.text, this.controlKey);

  final String text;

  /// Stable key of the lab control the guide outlines; never an answer.
  final String controlKey;
}

/// The "How to complete" panel of a lab phase.
final class MissionLabPanel {
  const MissionLabPanel(this.label, this.summary, this.steps);

  final String label;
  final String summary;
  final List<String> steps;
}

/// The phases whose work happens in a realistic lab instead of the standard
/// task panels (screens/simulation/components/labs). A lab records the same
/// evidence as the panels it replaces, so the definitions, contracts and
/// scoring stay unchanged; only the guidance has to speak the lab's terms.
abstract final class MissionLabPhases {
  static const _guides = {
    'coc2_m2_p2':
        MissionLabGuide(MissionContentData.labGuideCable, 'lab-cable-pin-1'),
    'coc4_m4_p1': MissionLabGuide(
        MissionContentData.labGuidePcieRemoval, 'lab-pcie-power'),
    'coc4_m4_p2': MissionLabGuide(
        MissionContentData.labGuidePcieInstall, 'lab-pcie-adapter'),
    'coc4_m4_p4': MissionLabGuide(
        MissionContentData.labGuidePcieCloseOut, 'lab-pcie-latch'),
  };

  static bool owns(String phaseId) => _guides.containsKey(phaseId);

  /// The main step of a lab phase, or null when no lab owns the phase.
  static MissionLabGuide? guide(String phaseId) => _guides[phaseId];

  /// The panel text of a lab phase, or null when no lab owns the phase. The
  /// T568B reference card exists in practice only, so only practice names it.
  static MissionLabPanel? panel(String phaseId, {required bool practice}) =>
      switch (phaseId) {
        'coc2_m2_p2' => MissionLabPanel(
            MissionContentData.labGuidanceCableLabel,
            MissionContentData.labGuidanceCableSummary,
            [
              ...MissionContentData.labGuidanceCableSteps,
              if (practice) MissionContentData.labGuidanceCableReference,
            ],
          ),
        'coc4_m4_p1' => const MissionLabPanel(
            MissionContentData.labGuidanceBenchLabel,
            MissionContentData.labGuidancePcieRemovalSummary,
            MissionContentData.labGuidanceBenchSteps,
          ),
        'coc4_m4_p2' => const MissionLabPanel(
            MissionContentData.labGuidanceBenchLabel,
            MissionContentData.labGuidancePcieInstallSummary,
            MissionContentData.labGuidanceInstallSteps,
          ),
        'coc4_m4_p4' => const MissionLabPanel(
            MissionContentData.labGuidanceBenchLabel,
            MissionContentData.labGuidancePcieCloseOutSummary,
            MissionContentData.labGuidanceBenchSteps,
          ),
        _ => null,
      };

  /// A practice completion condition of a lab phase (a state path such as
  /// `tool.retaining_screw` or `operation.protect_service_data`).
  static MissionLabGuide condition(String phaseId, String path) {
    final kind = path.split('.').first;
    return switch ((phaseId, kind)) {
      ('coc4_m4_p1', 'tool') => const MissionLabGuide(
          MissionContentData.labGuidePcieScrew, 'lab-pcie-screw'),
      ('coc4_m4_p1', 'operation' || 'setting') => const MissionLabGuide(
          MissionContentData.labGuidePcieContingency, 'lab-pcie-contingency'),
      _ => MissionLabGuide(MissionContentData.labGuideRemaining,
          _guides[phaseId]?.controlKey ?? 'mission-lab'),
    };
  }
}
