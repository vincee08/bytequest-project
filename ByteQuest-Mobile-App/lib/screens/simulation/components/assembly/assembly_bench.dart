import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/mission_content_data.dart';
import '../../../../data/mission_phase_guidance.dart';
import '../../runtime/mission_equipment_simulator.dart';
import '../../runtime/mission_runtime_models.dart';
import '../simulation_scene.dart';
import '../tool_tray.dart';
import 'assembly_bench_layout.dart';
import 'assembly_bench_model.dart';
import 'assembly_bench_painter.dart';

/// Drag payload of the bench: a part or a cable connector.
final class BenchDrag {
  const BenchDrag(this.kind, this.id);

  final String kind;
  final String id;
}

/// Realistic 2D assembly bench (COC1 M2). Parts are real photographs that
/// are dragged, or tapped then placed, into physically positioned slots of
/// the motherboard and case; keyed parts are rotated in 90° steps; levers,
/// latches and screws are operated where they are; cables are routed to
/// their headers. Every action goes through the shared evidence gateway and
/// equipment rules; the server replay stays authoritative.
class AssemblyBench extends StatefulWidget {
  const AssemblyBench({
    super.key,
    required this.definition,
    required this.phase,
    required this.state,
    required this.onAction,
    required this.onCameraChanged,
    required this.enabled,
    this.saving = false,
    this.feedback,
    this.highlightTarget,
    this.highlightObjectId,
    this.onModeChanged,
  });

  final MissionSimulationDefinition definition;
  final MissionPhaseDefinition phase;
  final MissionRuntimeState state;
  final MissionActionCallback onAction;
  final void Function(double scale, Offset offset) onCameraChanged;
  final bool enabled;
  final bool saving;
  final String? feedback;

  /// Non-null while the practice "Show me how" guide is active.
  final MissionGuideTarget? highlightTarget;
  final String? highlightObjectId;
  final ValueChanged<String>? onModeChanged;

  @override
  State<AssemblyBench> createState() => _AssemblyBenchState();
}

class _AssemblyBenchState extends State<AssemblyBench> {
  String? _selectedPart;
  String? _selectedCable;

  /// The tray tile being dragged right now (a part or cable id).
  BenchDrag? _dragging;
  final Map<String, int> _turns = {};
  bool _closeUp = false;
  bool _applying = false;
  String? _inspected;
  String? _hint;

  /// The hint answers the learner's latest gesture (a drop that missed every
  /// target, equipment that cannot be worked yet), so it shows over the
  /// feedback of the previous action until the next action.
  bool _hintFirst = false;
  String? _dismissed;
  String? _reportedMode;
  late final DateTime _mountedAt = DateTime.now();

  bool get _assessment => widget.state.mode == MissionRuntimeMode.assessment;
  bool get _interactive =>
      widget.enabled &&
      !_applying &&
      widget.phase.resolvedInteraction != InteractionFamily.review;

  @override
  void didUpdateWidget(covariant AssemblyBench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase.id != widget.phase.id) {
      _selectedPart = null;
      _selectedCable = null;
      _dragging = null;
      _closeUp = false;
      _inspected = null;
      _hint = null;
      _hintFirst = false;
      _dismissed = null;
      _reportedMode = null;
    }
    if (_selectedPart != null &&
        oldWidget.state.placements[_selectedPart] !=
            widget.state.placements[_selectedPart]) {
      _selectedPart = null;
    }
    if (_selectedCable != null &&
        oldWidget.state.connectedNodePairs.length !=
            widget.state.connectedNodePairs.length) {
      _selectedCable = null;
    }
    // A disabled bench rebuilds its tiles without a drag, so a drag that
    // was cut short never keeps the close-up open.
    if (!widget.enabled) _dragging = null;
  }

  Map<String, dynamic> get _equipment =>
      MissionEquipmentSimulator.map(widget.phase.presentation['equipment']);

  Map<String, dynamic> get _placementPanel =>
      widget.phase.resolvedInteraction == InteractionFamily.place
          ? widget.phase.presentation
          : MissionEquipmentSimulator.map(_equipment['placement']);

  Map<String, dynamic> _itemSpec(String id) =>
      MissionEquipmentSimulator.item(_placementPanel['items'], id);

  /// Quarter turns applied to a part; it only grows so the photograph always
  /// turns clockwise. The recorded orientation is the remainder.
  int _turnsFor(BenchPart part) =>
      _turns[part.id] ??
      (int.tryParse(part.initialOrientation) ?? 0) ~/ 90 % 4;

  String _orientation(BenchPart part) => '${_turnsFor(part) % 4 * 90}';

  /// Quarter turns a part is shown at. An installed part sits in its seating
  /// orientation, the only one the equipment rules accept, also after a
  /// restart; the nearest equivalent turn avoids a spin on seating.
  int _displayTurns(BenchPart part) {
    final turns = _turnsFor(part);
    final seating = int.tryParse(part.seatingOrientation ?? '');
    if (!part.placed || seating == null) return turns;
    return turns - (turns - seating ~/ 90) % 4;
  }

  /// Memory modules, the cooler and its fan cable go on the motherboard,
  /// whose slots and headers are told apart only in the close-up.
  bool _onBoard(String? partId, String? cableId) =>
      partId != null &&
          (_itemSpec(partId)['category'] == 'ddr4_dimm' ||
              partId == 'cooler') ||
      cableId == 'cooler_fan';

  BenchView _view(AssemblyBenchModel model) {
    final dragging = _dragging;
    // A part in hand, selected or being dragged from the tray, brings the
    // close-up, so a module dragged in the case view lands in the slot the
    // learner aims at instead of a neighbour drawn a few pixels away.
    final inHand = _onBoard(_selectedPart, _selectedCable) ||
        dragging != null &&
            _onBoard(dragging.kind == 'part' ? dragging.id : null,
                dragging.kind == 'cable' ? dragging.id : null);
    return AssemblyBenchLayout.viewFor(widget.phase.id,
        closeUp: _closeUp || inHand);
  }

  void _dragChanged(BenchDrag? drag) {
    if (!mounted) return;
    setState(() => _dragging = drag);
  }

  void _reportMode() {
    final mode = switch (widget.phase.resolvedInteraction) {
      InteractionFamily.inspect => 'inspect',
      InteractionFamily.connect => 'connect',
      _ => 'place',
    };
    if (_reportedMode == mode) return;
    _reportedMode = mode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onModeChanged?.call(mode);
    });
  }

  Future<void> _emit(String type, String? target, Map<String, dynamic> value,
      {String? hint}) async {
    if (!_interactive) return;
    setState(() {
      _applying = true;
      _hint = hint;
      _hintFirst = false;
      // The drop (or a tap) ends any drag in hand.
      _dragging = null;
      // A new action may repeat an earlier message; show it again.
      _dismissed = null;
    });
    try {
      await widget.onAction(type, target, value);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// A drop or canvas tap on a physical spot shared by stacked slots lands
  /// in the layer that takes the part (cooler over CPU); a part that fits
  /// none of them is still attempted on the slot it was released over.
  String _snapToLayer(AssemblyBenchModel model, String partId, String slotId) {
    final category = _itemSpec(partId)['category'];
    for (final group in AssemblyBenchLayout.stacked) {
      if (!group.contains(slotId)) continue;
      for (final candidate in group) {
        if (model.slot(candidate)?.categories.contains(category) == true) {
          return candidate;
        }
      }
    }
    return slotId;
  }

  Future<void> _place(String partId, String slotId, String method,
      {bool snap = false}) async {
    final model = AssemblyBenchModel.of(widget.phase, widget.state);
    final part = model.part(partId);
    if (part == null) return;
    if (snap) slotId = _snapToLayer(model, partId, slotId);
    await _emit('placement_attempted', slotId, {
      'item_id': partId,
      'destination_id': slotId,
      if (part.rotatable) 'orientation': _orientation(part),
      'input_method': method,
    });
  }

  /// What physically holds a seated part in place, or null when it can be
  /// lifted out: the DIMM latches hold a memory module, a mounted cooler and
  /// the closed load plate hold the processor, and the installed motherboard
  /// covers the I/O shield. The equipment rules accept any removal; the
  /// bench refuses an impossible one before anything is recorded.
  String? _removalHold(BenchPart part) {
    final settings = widget.state.equipmentState;
    final placements = widget.state.placements;
    if (_itemSpec(part.id)['category'] == 'ddr4_dimm' &&
        settings['dimm_latches'] != 'open') {
      return MissionContentData.benchHeldByLatches;
    }
    if (part.id == 'cpu') {
      if (placements['cooler'] != null) {
        return MissionContentData.benchHeldByCooler;
      }
      if (settings['cpu_lever'] != 'open') {
        return MissionContentData.benchHeldByLoadPlate;
      }
    }
    if (part.id == 'io_shield' && placements['motherboard'] != null) {
      return MissionContentData.benchHeldByMotherboard;
    }
    return null;
  }

  /// Equipment a mounted part blocks although the rules would allow it: the
  /// cooler presses on the socket load plate, so the lever cannot be lifted
  /// until the cooler is off. Closing a lever left open stays possible.
  String? _operationHold(BenchOperation operation) =>
      operation.id == 'open_cpu_lever' &&
              widget.state.placements['cooler'] != null
          ? MissionContentData.benchLeverUnderCooler
          : null;

  Future<void> _remove(String partId) async {
    final part = AssemblyBenchModel.of(widget.phase, widget.state).part(partId);
    if (part == null) return;
    final hold = _removalHold(part);
    if (hold != null) {
      _explain(
          _assessment ? MissionContentData.benchRemovalNotYet(part.label) : hold);
      return;
    }
    setState(() {
      // A part comes out the way it sat in its slot, so the hand and the
      // tray keep its seating orientation instead of the boxed one.
      _turns[partId] = _displayTurns(part);
      _selectedPart = null;
    });
    await _emit('placement_removed', partId,
        {'item_id': partId, 'input_method': 'tap'});
  }

  Future<void> _connect(String cableId, String headerId, String method) =>
      _emit('connection_created', headerId, {
        'source_id': cableId,
        'destination_id': headerId,
        'input_method': method,
      });

  Future<void> _operate(BenchOperation operation) {
    if (!operation.enabled) return Future.value();
    final hold = _operationHold(operation);
    if (hold != null) {
      _explain(_assessment
          ? MissionContentData.benchOperationNotYet(operation.label)
          : hold);
      return Future.value();
    }
    return _emit('equipment_operation', operation.id,
        const {'input_method': 'tap'});
  }

  Future<void> _inspect(BenchInspectable object) async {
    setState(() => _inspected = object.id);
    await _emit('object_inspected', object.id, const {'input_method': 'scene'});
  }

  void _rotate(BenchPart part) {
    setState(() => _turns[part.id] = _turnsFor(part) + 1);
  }

  /// A part or connector released over no slot, bay or header goes back to
  /// the tray. Say where it has to be released instead of doing nothing;
  /// nothing is recorded.
  void _dropMissed() {
    if (!mounted) return;
    setState(() {
      _dragging = null;
      _hint = MissionContentData.benchDropOnTarget;
      _hintFirst = true;
      _dismissed = null;
    });
  }

  /// A tap on equipment that cannot be worked yet (the mat ground stud
  /// before the strap is on) explains itself; nothing is recorded.
  void _operationBlocked(BenchOperation operation) =>
      _explain(MissionContentData.benchOperationNotYet(operation.label));

  /// A gesture the bench refuses before the rules (a held part, blocked
  /// equipment) answers over the feedback of the previous action.
  void _explain(String text) {
    if (!_interactive) return;
    setState(() {
      _hint = text;
      _hintFirst = true;
      _dismissed = null;
    });
  }

  void _selectPart(BenchPart part) {
    if (!_interactive) return;
    setState(() {
      _hintFirst = false;
      _selectedCable = null;
      _selectedPart = _selectedPart == part.id ? null : part.id;
      _hint = _selectedPart == null
          ? null
          : part.placed
              ? MissionContentData.benchInstalledSelected(part.label)
              : _assessment
                  ? MissionContentData.benchSelectedNeutral(part.label)
                  : MissionContentData.benchPartSelected(part.label);
    });
  }

  void _selectCable(BenchCable cable) {
    if (!_interactive) return;
    setState(() {
      _hintFirst = false;
      _selectedPart = null;
      _selectedCable = _selectedCable == cable.id ? null : cable.id;
      _hint = _selectedCable == null
          ? null
          : _assessment
              ? MissionContentData.benchSelectedNeutral(cable.label)
              : MissionContentData.benchCableSelected(cable.label);
    });
  }

  void _clearSelection() => setState(() {
        _selectedPart = null;
        _selectedCable = null;
        _hint = null;
        _hintFirst = false;
      });

  void _tapSlot(String slotId, {bool snap = false}) {
    final part = _selectedPart;
    if (part == null || !_interactive) return;
    final model = AssemblyBenchModel.of(widget.phase, widget.state);
    if (model.part(part)?.placed == true) return;
    unawaited(_place(part, slotId, 'tap', snap: snap));
  }

  void _tapHeader(String headerId) {
    final cable = _selectedCable;
    if (cable == null || !_interactive) return;
    unawaited(_connect(cable, headerId, 'tap'));
  }

  /// The practice guide focuses the current bench step; assessment never.
  Set<String> _guideFocus(AssemblyBenchModel model) {
    if (_assessment || widget.highlightTarget == null) return const {};
    final step = model.currentStep;
    if (step?.focusId == null) return const {};
    return {step!.focusId!};
  }

  /// Where the guide outline goes on the bench: a focused part outlines the
  /// slots it physically fits and a focused cable its compatible headers, in
  /// the coordinates of the current view; levers, latches and screws outline
  /// their own spot. A part in the tray has no spot of its own on the bench.
  Set<String> _focusTargets(AssemblyBenchModel model, Set<String> focus) {
    final targets = <String>{};
    for (final id in focus) {
      final part = model.part(id);
      if (part != null) {
        if (!part.placed) {
          targets.addAll(model
              .compatibleSlots(id, _itemSpec(id), widget.state.placements)
              .map((slot) => slot.id));
        }
      } else if (model.cable(id) != null) {
        targets.addAll(model.compatibleHeaders(id).map((header) => header.id));
      } else {
        targets.add(id);
      }
    }
    return targets;
  }

  Set<String> _compatible(AssemblyBenchModel model) {
    if (_assessment) return const {};
    if (_selectedPart != null && model.part(_selectedPart)?.placed != true) {
      return model
          .compatibleSlots(
              _selectedPart!, _itemSpec(_selectedPart!), widget.state.placements)
          .map((slot) => slot.id)
          .toSet();
    }
    if (_selectedCable != null) {
      return model
          .compatibleHeaders(_selectedCable!)
          .map((header) => header.id)
          .toSet();
    }
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    _reportMode();
    final model = AssemblyBenchModel.of(widget.phase, widget.state);
    final view = _view(model);
    final focus = _guideFocus(model);
    final compatible = _compatible(model);
    final outlined = {...compatible, ..._focusTargets(model, focus)};
    final held = {
      for (final operation in model.operations)
        if (_operationHold(operation) != null) operation.id,
    };
    final reducedMotion = MediaQuery.disableAnimationsOf(context) ||
        widget.state.reducedMotion;
    // The part in hand, when it carries an orientation marker.
    final selected = model.part(_selectedPart);
    final keyed = selected != null &&
            !selected.placed &&
            AssemblyBenchLayout.markers.containsKey(selected.id)
        ? selected
        : null;
    final viewTitle = switch (view) {
      BenchView.mat => MissionContentData.benchMatView,
      BenchView.board => MissionContentData.benchBoardView,
      BenchView.chassis => MissionContentData.benchChassisView,
    };
    final canToggle = widget.phase.id.endsWith('_p5');
    final information = (_hintFirst ? _hint : null) ??
        widget.feedback ??
        _hint ??
        (_inspected == null
            ? null
            : model.inspectables
                .where((object) => object.id == _inspected)
                .map((object) => '${object.label}: ${_assessment ? MissionContentData.benchAssessmentInspection[object.id] ?? object.inspection : object.inspection}')
                .firstOrNull);
    return LayoutBuilder(builder: (context, constraints) {
      // On short screens the step header floats over the canvas so the
      // bench keeps its working height.
      final roomy = constraints.maxHeight >= 440;
      final header = _BenchHeader(
        model: model,
        assessment: _assessment,
        phaseTitle: widget.phase.title,
        startedAt: model.startedAt ?? _mountedAt,
        maxLines: roomy ? 2 : 1,
        floating: !roomy,
      );
      return Column(
        key: const ValueKey('assembly-bench'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (roomy) header,
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              SimulationScene(
                key: ValueKey('bench-scene-${view.name}-${widget.phase.id}'),
                scene: SimulationSceneDefinition(
                  id: '${widget.definition.id}_assembly_bench',
                  objects: const [],
                  initialStatus: {'title': viewTitle, 'prompt': viewTitle},
                ),
                compactToolbar: true,
                showObjectsButton: false,
                enabled: widget.enabled,
                panEnabled: widget.enabled,
                scrollEnabled: !widget.saving,
                initialCameraScale: widget.state.cameraScale,
                initialCameraOffset: Offset(
                    widget.state.cameraOffsetX, widget.state.cameraOffsetY),
                onCameraChanged: widget.onCameraChanged,
                onObjectSelected: (_) {},
                backgroundRenderer: _BenchCanvas(
                  model: model,
                  view: view,
                  state: widget.state,
                  interactive: _interactive,
                  assessment: _assessment,
                  reducedMotion: reducedMotion,
                  selectedPart: _selectedPart,
                  selectedCable: _selectedCable,
                  compatible: compatible,
                  focus: focus,
                  outlined: outlined,
                  held: held,
                  onTapSlot: (slot) => _tapSlot(slot, snap: true),
                  onTapHeader: _tapHeader,
                  onDropPart: (part, slot) =>
                      unawaited(_place(part, slot, 'drag', snap: true)),
                  onDropCable: (cable, header) =>
                      unawaited(_connect(cable, header, 'drag')),
                  onOperate: (operation) => unawaited(_operate(operation)),
                  onOperationBlocked: _operationBlocked,
                  onInspect: (object) => unawaited(_inspect(object)),
                ),
              ),
              // The floating step header and the preview of the part in hand
              // never block a drop or a tap.
              if (!roomy || keyed != null)
                Positioned(
                  top: 54,
                  left: 6,
                  right: 6,
                  child: IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!roomy) header,
                        if (keyed != null)
                          Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: _PartPreview(
                                part: keyed,
                                turns: _turnsFor(keyed),
                                reducedMotion: reducedMotion,
                                compact: !roomy,
                                assessment: _assessment,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (information != null && information != _dismissed)
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: _BenchInformation(
                    text: information,
                    saving: widget.saving,
                    onDismiss: () => setState(() => _dismissed = information),
                  ),
                ),
            ]),
          ),
          _BenchTray(
            model: model,
            assessment: _assessment,
            enabled: _interactive,
            reducedMotion: reducedMotion,
            selectedPart: _selectedPart,
            selectedCable: _selectedCable,
            compatible: compatible,
            focus: focus,
            turnsFor: _displayTurns,
            closeUp: canToggle ? view == BenchView.board : null,
            onToggleView: () =>
                setState(() => _closeUp = view != BenchView.board),
            onSelectPart: _selectPart,
            onSelectCable: _selectCable,
            onDragChanged: _dragChanged,
            onDropMissed: _dropMissed,
            onRotate: _rotate,
            onRemove: (part) => unawaited(_remove(part.id)),
            onCancel: _clearSelection,
            onTapSlot: _tapSlot,
            onTapHeader: _tapHeader,
            onOperate: (operation) => unawaited(_operate(operation)),
            onInspect: (object) => unawaited(_inspect(object)),
          ),
        ],
      );
    });
  }
}

class _BenchHeader extends StatelessWidget {
  const _BenchHeader({
    required this.model,
    required this.assessment,
    required this.phaseTitle,
    required this.startedAt,
    required this.maxLines,
    required this.floating,
  });

  final AssemblyBenchModel model;
  final bool assessment;
  final String phaseTitle;
  final DateTime startedAt;
  final int maxLines;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final step = model.currentStep;
    final text = assessment
        ? MissionContentData.benchAssessmentHeader
        : model.steps.isEmpty
            ? phaseTitle
            : step == null
                ? MissionContentData.benchStepsDone(model.steps.length)
                : MissionContentData.benchStepPosition(
                    model.currentStepIndex + 1, model.steps.length, step.label);
    return Container(
      key: const ValueKey('assembly-bench-header'),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: floating
          ? BoxDecoration(
              color: AppTheme.backgroundPaleBlue.withValues(alpha: .94),
              borderRadius: AppTheme.radiusXs,
              border: Border.all(color: AppTheme.borderLight),
            )
          : const BoxDecoration(
              color: AppTheme.backgroundPaleBlue,
              border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
            ),
      child: LayoutBuilder(builder: (context, constraints) {
        final step = Semantics(
          liveRegion: true,
          child: Text(
            text,
            key: const ValueKey('assembly-bench-step'),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.labelMedium.copyWith(color: AppTheme.navy),
          ),
        );
        final metrics = Row(mainAxisSize: MainAxisSize.min, children: [
          _ElapsedClock(startedAt: startedAt),
          const SizedBox(width: 8),
          Semantics(
            label: MissionContentData.benchCountsSemantics(model.validCount,
                model.invalidCount, model.correctionCount, model.faultCount),
            excludeSemantics: true,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle_outline,
                  size: 16, color: AppTheme.accentGreen),
              Text(' ${model.validCount}',
                  key: const ValueKey('assembly-bench-valid-count'),
                  style: AppTheme.labelSmall),
              const SizedBox(width: 6),
              const Icon(Icons.highlight_off,
                  size: 16, color: AppTheme.accentRed),
              Text(' ${model.invalidCount}',
                  key: const ValueKey('assembly-bench-invalid-count'),
                  style: AppTheme.labelSmall),
              if (model.correctionCount > 0) ...[
                const SizedBox(width: 6),
                const Icon(Icons.autorenew,
                    size: 16, color: AppTheme.textMedium),
                Text(' ${model.correctionCount}', style: AppTheme.labelSmall),
              ],
              if (model.faultCount > 0) ...[
                const SizedBox(width: 6),
                const Icon(Icons.report_problem_outlined,
                    size: 16, color: AppTheme.accentOrange),
                Text(' ${model.faultCount}',
                    key: const ValueKey('assembly-bench-fault-count'),
                    style: AppTheme.labelSmall),
              ],
            ]),
          ),
          const SizedBox(width: 6),
        ]);
        // Large text or a narrow panel stacks the timer under the step.
        final stacked = constraints.maxWidth < 380 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              step,
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: metrics),
              ),
            ],
          );
        }
        return Row(children: [
          Expanded(child: step),
          const SizedBox(width: 6),
          metrics,
        ]);
      }),
    );
  }
}

class _ElapsedClock extends StatefulWidget {
  const _ElapsedClock({required this.startedAt});

  final DateTime startedAt;

  @override
  State<_ElapsedClock> createState() => _ElapsedClockState();
}

class _ElapsedClockState extends State<_ElapsedClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().toUtc().difference(widget.startedAt.toUtc());
    final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
    final text = seconds >= 3600
        ? '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
        : '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Semantics(
      label: MissionContentData.benchElapsedSemantics(text),
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.timer_outlined, size: 16, color: AppTheme.textMedium),
        Text(' $text',
            key: const ValueKey('assembly-bench-elapsed'),
            style: AppTheme.labelSmall),
      ]),
    );
  }
}

class _BenchCanvas extends StatelessWidget {
  const _BenchCanvas({
    required this.model,
    required this.view,
    required this.state,
    required this.interactive,
    required this.assessment,
    required this.reducedMotion,
    required this.selectedPart,
    required this.selectedCable,
    required this.compatible,
    required this.focus,
    required this.outlined,
    required this.held,
    required this.onTapSlot,
    required this.onTapHeader,
    required this.onDropPart,
    required this.onDropCable,
    required this.onOperate,
    required this.onOperationBlocked,
    required this.onInspect,
  });

  final AssemblyBenchModel model;
  final BenchView view;
  final MissionRuntimeState state;
  final bool interactive;
  final bool assessment;
  final bool reducedMotion;
  final String? selectedPart;
  final String? selectedCable;
  final Set<String> compatible;
  final Set<String> focus;

  /// Slots, headers and operation spots outlined on the canvas (compatible
  /// targets and the practice guide focus), drawn in canvas units so the
  /// outline follows the camera at any zoom, pan and viewport size.
  final Set<String> outlined;

  /// Operations a mounted part physically blocks (the socket lever under
  /// the cooler): no ring on the bench, like equipment not workable yet.
  final Set<String> held;
  final ValueChanged<String> onTapSlot;
  final ValueChanged<String> onTapHeader;
  final void Function(String part, String slot) onDropPart;
  final void Function(String cable, String header) onDropCable;
  final ValueChanged<BenchOperation> onOperate;
  final ValueChanged<BenchOperation> onOperationBlocked;
  final ValueChanged<BenchInspectable> onInspect;

  bool get _boardInstalled => state.placements['motherboard'] != null;

  @override
  Widget build(BuildContext context) {
    final settings = state.equipmentState;
    final children = <Widget>[
      const Positioned.fill(child: ColoredBox(color: Color(0xFFE9EEF6))),
    ];
    switch (view) {
      case BenchView.mat:
        children.add(Positioned.fill(
          child: CustomPaint(
            painter: AssemblyBenchPainter(
              view: view,
              settings: settings,
              placements: state.placements,
              links: state.connectedNodePairs,
              highlighted: const {},
              boardInstalled: false,
            ),
          ),
        ));
        for (final object in model.inspectables) {
          final rect = AssemblyBenchLayout.matParts[object.id];
          if (rect == null) continue;
          children.add(Positioned.fromRect(
            rect: rect,
            child: _InspectablePart(
              object: object,
              enabled: interactive,
              focused: focus.contains(object.id),
              onTap: () => onInspect(object),
            ),
          ));
        }
        // The wrist strap lies beside the mat; the strap and the mat's
        // ground stud are labelled in both modes. Labels name the object,
        // never the step.
        final strap = AssemblyBenchLayout.operation('wear_wrist_strap', view);
        if (strap != null) {
          children.add(Positioned.fromRect(
            rect: strap.deflate(12),
            child: const IgnorePointer(
              child: Image(
                image: AssetImage(AssemblyBenchLayout.strapAsset),
                fit: BoxFit.contain,
              ),
            ),
          ));
        }
        for (final label in MissionContentData.benchHotspotLabels.entries) {
          final rect = AssemblyBenchLayout.hotspotLabel(label.key);
          if (rect == null) continue;
          children.add(Positioned.fromRect(
            rect: rect,
            child: _SceneLabel(
                key: ValueKey('bench-hotspot-label-${label.key}'),
                text: label.value),
          ));
        }
      case BenchView.board:
        children.add(Positioned.fromRect(
          rect: AssemblyBenchLayout.boardImageRect(view),
          child: const IgnorePointer(
            child: Image(
              image: AssetImage(AssemblyBenchLayout.boardAsset),
              fit: BoxFit.fill,
            ),
          ),
        ));
      case BenchView.chassis:
        children.add(Positioned.fromRect(
          rect: AssemblyBenchLayout.caseRect,
          child: const IgnorePointer(
            child: Image(
              image: AssetImage(AssemblyBenchLayout.caseAsset),
              fit: BoxFit.fill,
            ),
          ),
        ));
        if (_boardInstalled) {
          children.add(Positioned.fromRect(
            rect: AssemblyBenchLayout.boardImageRect(view),
            child: _Seated(
              key: ValueKey('bench-placed-motherboard-${state.placements['motherboard']}'),
              reducedMotion: reducedMotion,
              child: const Image(
                image: AssetImage(AssemblyBenchLayout.boardAsset),
                fit: BoxFit.fill,
              ),
            ),
          ));
        }
    }
    if (view != BenchView.mat) {
      children.add(Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: AssemblyBenchPainter(
              view: view,
              settings: settings,
              placements: state.placements,
              links: const {},
              highlighted: const {},
              boardInstalled: _boardInstalled,
            ),
          ),
        ),
      ));
      // Photographs of seated parts sit exactly in their slot rectangles.
      for (final entry in state.placements.entries) {
        if (entry.key == 'motherboard' ||
            entry.key == 'io_shield' ||
            entry.key.startsWith('ram_')) {
          continue;
        }
        if (view == BenchView.chassis &&
            AssemblyBenchLayout.boardDestinations.contains(entry.value) &&
            !_boardInstalled) {
          continue;
        }
        final rect = AssemblyBenchLayout.slot(entry.value, view);
        final asset = AssemblyBenchLayout.partAssets[entry.key];
        if (rect == null || asset == null) continue;
        // The rules seat a keyed part only at its seating orientation (0°),
        // so its marker sits over the mark on the bench.
        final keyed = AssemblyBenchLayout.markers.containsKey(entry.key);
        Widget photo(double? extent) => keyed
            ? _PartImage(
                id: entry.key,
                asset: asset,
                turns: 0,
                reducedMotion: reducedMotion,
                size: extent)
            : Image(image: AssetImage(asset), fit: BoxFit.contain);
        final content = AssemblyBenchLayout.bayContent[entry.key];
        children.add(Positioned.fromRect(
          key: ValueKey('bench-placed-${entry.key}'),
          rect: rect,
          child: _Seated(
            key: ValueKey('bench-seat-${entry.key}-${entry.value}'),
            reducedMotion: reducedMotion,
            child: content == null
                ? photo(null)
                : _FilledSeat(content: content, builder: photo),
          ),
        ));
      }
      // Thermal compound sits on the processor's heat spreader, so it is
      // drawn over the seated CPU photograph (the board painter is beneath
      // the photographs) until the cooler covers it.
      final socket = AssemblyBenchLayout.slot('cpu_socket', view);
      if (view == BenchView.board &&
          socket != null &&
          settings['thermal_compound'] == true &&
          state.placements['cpu'] != null &&
          state.placements['cooler'] == null) {
        children.add(Positioned.fromRect(
          key: const ValueKey('bench-thermal-compound'),
          rect: socket,
          child: const IgnorePointer(
              child: CustomPaint(painter: _ThermalCompoundPainter())),
        ));
      }
      children.add(Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            key: const ValueKey('assembly-bench-wiring'),
            painter: _WiringPainter(
              view: view,
              links: state.connectedNodePairs,
              highlighted: outlined,
            ),
          ),
        ),
      ));
    }
    // Levers, latches, screws and the strap are hotspots only while the
    // operation is physically possible and would change something; the tray
    // lists them all. On the mat, where the strap and the ground stud are
    // always in view, a tap on equipment that cannot be worked yet explains
    // why instead of doing nothing.
    final rings = <_Ring>[];
    for (final operation in model.operations) {
      final rect = AssemblyBenchLayout.operation(operation.id, view);
      if (rect == null || operation.idle) continue;
      final available = operation.enabled && !held.contains(operation.id);
      if (!available && view != BenchView.mat) continue;
      rings.add(_Ring(operation, _minimum(rect, 72),
          _minimum(rect, AssemblyBenchLayout.ringReach), available));
    }
    final hotspots = [
      for (final ring in rings)
        if (ring.available) (ring.operation, ring.area),
    ];
    // A drawn ring is about 24 dp on a phone with the whole bench in view.
    // Beneath the rings, slots and headers, a tap beside a ring (within its
    // reach, at least 48 dp across) goes to the nearest ring; a slot or
    // header over that spot still takes a tap while a part or cable is in
    // hand. Only the reach areas take a tap, so a part on the mat keeps its
    // own.
    for (final ring in rings) {
      children.add(Positioned.fromRect(
        rect: ring.reach,
        child: GestureDetector(
          key: ValueKey('bench-ring-reach-${ring.operation.id}'),
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          onTapUp: interactive
              ? (details) =>
                  _reachTap(ring.reach.topLeft + details.localPosition, rings)
              : null,
        ),
      ));
    }
    for (final ring in rings) {
      final (operation, area, available) =
          (ring.operation, ring.area, ring.available);
      children.add(Positioned.fromRect(
        rect: area,
        child: _OperationHotspot(
          operation: operation,
          enabled: interactive,
          available: available,
          focused: focus.contains(operation.id),
          onTap: available
              ? () => onOperate(operation)
              : () => onOperationBlocked(operation),
        ),
      ));
    }
    // Drop and tap targets sit on top but never stop a hit test, so a ring
    // beneath always takes its tap, also while a part or cable is in hand.
    if (view != BenchView.mat) children.addAll(_targets(context, hotspots));
    return Semantics(
      label: '${switch (view) {
        BenchView.mat => MissionContentData.benchMatView,
        BenchView.board => MissionContentData.benchBoardView,
        BenchView.chassis => MissionContentData.benchChassisView,
      }}. ${MissionContentData.benchPartsHint}',
      container: true,
      child: Stack(clipBehavior: Clip.hardEdge, children: children),
    );
  }

  static Rect _minimum(Rect rect, double minimum) => Rect.fromCenter(
      center: rect.center,
      width: rect.width < minimum ? minimum : rect.width,
      height: rect.height < minimum ? minimum : rect.height);

  /// A tap at [point] (canvas units) beside the rings: the ring nearest to
  /// it among those whose reach holds it takes the tap; equipment that
  /// cannot be worked yet explains itself. Elsewhere nothing happens.
  void _reachTap(Offset point, List<_Ring> rings) {
    _Ring? nearest;
    var best = double.infinity;
    for (final ring in rings) {
      if (!ring.reach.contains(point)) continue;
      final distance = (ring.area.center - point).distance;
      if (distance < best) {
        best = distance;
        nearest = ring;
      }
    }
    if (nearest == null) return;
    nearest.available
        ? onOperate(nearest.operation)
        : onOperationBlocked(nearest.operation);
  }

  /// A tap at [point] (canvas units) on a slot or header: a working ring
  /// there (a lever beside the socket, the thermal compound on the CPU, a
  /// screw over a bay) takes it, as it would with nothing in hand; otherwise
  /// the part or cable in hand goes to [fallback].
  void _tapAt(Offset point, List<(BenchOperation, Rect)> hotspots,
      VoidCallback fallback) {
    for (final (operation, area) in hotspots) {
      if (area.contains(point)) {
        onOperate(operation);
        return;
      }
    }
    fallback();
  }

  List<Widget> _targets(
      BuildContext context, List<(BenchOperation, Rect)> hotspots) {
    final widgets = <Widget>[];
    // Larger slots first, so a smaller slot inside one (the CPU socket under
    // the cooler mount) is hit first.
    final slots = [
      for (final slot in model.slots)
        if (AssemblyBenchLayout.target(slot.id, view) case final rect?)
          (slot, rect),
    ]..sort((a, b) => (b.$2.width * b.$2.height)
        .compareTo(a.$2.width * a.$2.height));
    for (final (slot, rect) in slots) {
      final occupant = state.placements.entries
          .where((entry) => entry.value == slot.id)
          .map((entry) => model.part(entry.key)?.label ?? entry.key)
          .firstOrNull;
      final occupantId = state.placements.entries
          .where((entry) => entry.value == slot.id)
          .map((entry) => entry.key)
          .firstOrNull;
      widgets.add(Positioned.fromRect(
        key: ValueKey('bench-slot-${slot.id}'),
        rect: rect,
        child: Semantics(
          button: true,
          label: MissionContentData.benchSlotSemantics(slot.label, occupant),
          // A screen-reader tap has no position on the bench, so it always
          // installs the part in hand; only a pointer tap can land on a ring.
          onTap: interactive && selectedPart != null && occupantId == null
              ? () => onTapSlot(slot.id)
              : null,
          child: DragTarget<BenchDrag>(
            onWillAcceptWithDetails: (details) =>
                interactive && details.data.kind == 'part',
            onAcceptWithDetails: (details) =>
                onDropPart(details.data.id, slot.id),
            builder: (context, candidates, _) => GestureDetector(
              behavior: HitTestBehavior.translucent,
              excludeFromSemantics: true,
              onTapUp: interactive && selectedPart != null && occupantId == null
                  ? (details) => _tapAt(rect.topLeft + details.localPosition,
                      hotspots, () => onTapSlot(slot.id))
                  : null,
              child: _TargetFrame(
                hovering: candidates.isNotEmpty,
                compatible: !assessment && compatible.contains(slot.id),
              ),
            ),
          ),
        ),
      ));
    }
    for (final header in model.headers) {
      final rect = AssemblyBenchLayout.target(header.id, view);
      if (rect == null) continue;
      widgets.add(Positioned.fromRect(
        key: ValueKey('bench-header-${header.id}'),
        rect: rect,
        child: Semantics(
          button: true,
          label: MissionContentData.benchHeaderSemantics(header.label),
          onTap: interactive && selectedCable != null
              ? () => onTapHeader(header.id)
              : null,
          child: DragTarget<BenchDrag>(
            onWillAcceptWithDetails: (details) =>
                interactive && details.data.kind == 'cable',
            onAcceptWithDetails: (details) =>
                onDropCable(details.data.id, header.id),
            builder: (context, candidates, _) => GestureDetector(
              behavior: HitTestBehavior.translucent,
              excludeFromSemantics: true,
              onTapUp: interactive && selectedCable != null
                  ? (details) => _tapAt(rect.topLeft + details.localPosition,
                      hotspots, () => onTapHeader(header.id))
                  : null,
              child: _TargetFrame(
                hovering: candidates.isNotEmpty,
                compatible: !assessment && compatible.contains(header.id),
              ),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }
}

/// One ring on the bench: its drawn [area], the larger [reach] a tap may
/// land in, and whether the equipment can be worked now.
final class _Ring {
  const _Ring(this.operation, this.area, this.reach, this.available);

  final BenchOperation operation;
  final Rect area;
  final Rect reach;
  final bool available;
}

/// A square part photograph drawn so its visible [content] (fractions of
/// the image), not the transparent margin around it, fills the bay it is
/// seated in, at the photograph's own proportions.
class _FilledSeat extends StatelessWidget {
  const _FilledSeat({required this.content, required this.builder});

  final Rect content;
  final Widget Function(double extent) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final extent = math.min(
            box.maxWidth / content.width, box.maxHeight / content.height);
        return Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: (box.maxWidth - content.width * extent) / 2 -
                content.left * extent,
            top: (box.maxHeight - content.height * extent) / 2 -
                content.top * extent,
            width: extent,
            height: extent,
            child: builder(extent),
          ),
        ]);
      });
}

/// Seat animation: the part settles into its slot (none with reduced motion).
class _Seated extends StatelessWidget {
  const _Seated({super.key, required this.reducedMotion, required this.child});

  final bool reducedMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: reducedMotion ? 1 : 1.12, end: 1),
        duration: reducedMotion
            ? Duration.zero
            : AppTheme.simulationTransitionDuration,
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: IgnorePointer(child: child),
      );
}

class _TargetFrame extends StatelessWidget {
  const _TargetFrame({required this.hovering, required this.compatible});

  final bool hovering;
  final bool compatible;

  // The frame is paint only. A decorated box reports a hit anywhere inside
  // it, which would stop the hit test at the slot and leave the lever,
  // thermal-compound and screw rings beneath it dead. The slot's own tap
  // detector and drag target stay hit (both are translucent).
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                hovering ? AppTheme.primaryBlue.withValues(alpha: .14) : null,
            border: hovering || compatible
                ? Border.all(
                    color: hovering ? AppTheme.primaryBlue : AppTheme.skyBlue,
                    width: hovering ? 5 : 4)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const SizedBox.expand(),
        ),
      );
}

/// A pea-sized dot of grey thermal compound in the middle of the socket
/// rectangle (the processor's heat spreader), with a rim and a highlight so
/// it reads on the silver photograph.
class _ThermalCompoundPainter extends CustomPainter {
  const _ThermalCompoundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 60;
    final centre = size.center(Offset.zero);
    canvas.drawCircle(
        centre, 6.5 * unit, Paint()..color = const Color(0xFF8E96A1));
    canvas.drawCircle(
        centre,
        6.5 * unit,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * unit
          ..color = const Color(0xFF5F6874));
    canvas.drawCircle(centre.translate(-2 * unit, -2 * unit), 1.8 * unit,
        Paint()..color = const Color(0xFFC3C9D1));
  }

  @override
  bool shouldRepaint(covariant _ThermalCompoundPainter oldDelegate) => false;
}

class _WiringPainter extends AssemblyBenchPainter {
  _WiringPainter(
      {required super.view, required super.links, required super.highlighted})
      : super(settings: const {}, placements: const {}, boardInstalled: false);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / AssemblyBenchLayout.canvas.width,
        size.height / AssemblyBenchLayout.canvas.height);
    paintWiring(canvas);
    canvas.restore();
  }
}

class _OperationHotspot extends StatelessWidget {
  const _OperationHotspot({
    required this.operation,
    required this.enabled,
    required this.focused,
    required this.onTap,
    this.available = true,
  });

  final BenchOperation operation;
  final bool enabled;
  final bool focused;
  final VoidCallback onTap;

  /// False for equipment that cannot be worked yet: no ring, and a tap only
  /// explains why.
  final bool available;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: enabled && available,
        label: MissionContentData.benchOperationSemantics(
            operation.label, enabled && available),
        child: GestureDetector(
          key: ValueKey(available
              ? 'bench-hotspot-${operation.id}'
              : 'bench-hotspot-blocked-${operation.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: focused
                    ? AppTheme.primaryBlue
                    : enabled && available
                        ? AppTheme.accentYellow
                        : Colors.transparent,
                width: focused ? 6 : 4,
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
}

class _InspectablePart extends StatelessWidget {
  const _InspectablePart({
    required this.object,
    required this.enabled,
    required this.focused,
    required this.onTap,
  });

  final BenchInspectable object;
  final bool enabled;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: MissionContentData.benchInspectSemantics(
            object.label, object.inspected),
        child: GestureDetector(
          key: ValueKey('bench-inspect-${object.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Stack(fit: StackFit.expand, children: [
            if (object.asset != null)
              Image(image: AssetImage(object.asset!), fit: BoxFit.contain),
            if (object.inspected)
              const Align(
                alignment: Alignment.topRight,
                child: Icon(Icons.check_circle,
                    size: 48, color: AppTheme.accentGreen),
              ),
            if (focused)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primaryBlue, width: 6),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
          ]),
        ),
      );
}

class _BenchInformation extends StatelessWidget {
  const _BenchInformation(
      {required this.text, required this.saving, required this.onDismiss});

  final String text;
  final bool saving;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
        color: AppTheme.softBlueAccent,
        elevation: 1,
        borderRadius: AppTheme.radiusSm,
        child: Row(children: [
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                saving ? MissionContentData.workspaceSavingLabel : text,
                key: const ValueKey('assembly-bench-information'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySmall,
              ),
            ),
          ),
          IconButton(
            tooltip: MissionContentData.benchReadMore,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                scrollable: true,
                title: const Text(MissionContentData.workspaceFeedbackLabel),
                content: Text(text),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text(MissionContentData.backLabel)),
                ],
              ),
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          IconButton(
            key: const ValueKey('assembly-bench-information-dismiss'),
            tooltip: MissionContentData.benchDismissInformation,
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ]),
      );
}

class _BenchTray extends StatelessWidget {
  const _BenchTray({
    required this.model,
    required this.assessment,
    required this.enabled,
    required this.reducedMotion,
    required this.selectedPart,
    required this.selectedCable,
    required this.compatible,
    required this.focus,
    required this.turnsFor,
    required this.closeUp,
    required this.onToggleView,
    required this.onSelectPart,
    required this.onSelectCable,
    required this.onDragChanged,
    required this.onDropMissed,
    required this.onRotate,
    required this.onRemove,
    required this.onCancel,
    required this.onTapSlot,
    required this.onTapHeader,
    required this.onOperate,
    required this.onInspect,
  });

  final AssemblyBenchModel model;
  final bool assessment;
  final bool enabled;
  final bool reducedMotion;
  final String? selectedPart;
  final String? selectedCable;
  final Set<String> compatible;
  final Set<String> focus;
  final int Function(BenchPart part) turnsFor;
  final ValueChanged<BenchDrag?> onDragChanged;

  /// A drag released over no slot, bay or header.
  final VoidCallback onDropMissed;

  /// Non-null where the learner can switch between the case and the
  /// motherboard close-up (the power-on test bench).
  final bool? closeUp;
  final VoidCallback onToggleView;
  final ValueChanged<BenchPart> onSelectPart;
  final ValueChanged<BenchCable> onSelectCable;
  final ValueChanged<BenchPart> onRotate;
  final ValueChanged<BenchPart> onRemove;
  final VoidCallback onCancel;
  final ValueChanged<String> onTapSlot;
  final ValueChanged<String> onTapHeader;
  final ValueChanged<BenchOperation> onOperate;
  final ValueChanged<BenchInspectable> onInspect;

  @override
  Widget build(BuildContext context) {
    final part = model.part(selectedPart);
    final cable = model.cable(selectedCable);
    final children = <Widget>[
      if (closeUp != null)
        _TrayButton(
          key: const ValueKey('assembly-bench-toggle-view'),
          icon: closeUp!
              ? Icons.zoom_out_map_rounded
              : Icons.developer_board_outlined,
          label: closeUp!
              ? MissionContentData.benchChassisView
              : MissionContentData.benchBoardView,
          semantics: closeUp!
              ? MissionContentData.benchShowCase
              : MissionContentData.benchShowBoard,
          onPressed: onToggleView,
        ),
    ];
    if (part != null) {
      children.add(_PartChip(
        part: part,
        turns: turnsFor(part),
        selected: true,
        enabled: enabled,
        focused: false,
        reducedMotion: reducedMotion,
        onTap: () => onSelectPart(part),
        onDoubleTap: part.rotatable && !part.placed ? () => onRotate(part) : null,
        onDragChanged: onDragChanged,
        onDropMissed: onDropMissed,
      ));
      if (part.placed) {
        children.add(_TrayButton(
          key: const ValueKey('bench-remove'),
          icon: Icons.eject_outlined,
          label: MissionContentData.benchRemoveLabel,
          semantics: MissionContentData.benchRemoveSemantics(part.label),
          onPressed: enabled ? () => onRemove(part) : null,
        ));
      } else {
        if (part.rotatable) {
          final position =
              benchMarkerDescription(part.id, turnsFor(part), angle: false);
          children.add(_TrayButton(
            key: const ValueKey('bench-rotate'),
            icon: Icons.rotate_right_rounded,
            label: MissionContentData.benchRotateLabel,
            // Assessment names only where the marker is; an angle would
            // read the same at the one seating orientation of every part.
            semantics: assessment && position != null
                ? MissionContentData.benchRotatePositionSemantics(
                    part.label, position)
                : MissionContentData.benchRotateSemantics(
                    part.label, '${turnsFor(part) % 4 * 90}'),
            onPressed: enabled ? () => onRotate(part) : null,
          ));
        }
        for (final slot in model.slots) {
          // A slot that already holds a part says so and takes no install,
          // like the slot on the bench, so it never spends an attempt.
          final occupant = model.parts
              .where((candidate) => candidate.placedAt == slot.id)
              .map((candidate) => candidate.label)
              .firstOrNull;
          children.add(_TrayButton(
            key: ValueKey('bench-slot-chip-${slot.id}'),
            icon: Icons.download_rounded,
            label: MissionContentData.benchInstallChip(slot.label),
            semantics: MissionContentData.benchSlotSemantics(slot.label, occupant),
            emphasised: !assessment && compatible.contains(slot.id),
            onPressed:
                enabled && occupant == null ? () => onTapSlot(slot.id) : null,
          ));
        }
      }
      children.add(_TrayButton(
        key: const ValueKey('bench-cancel'),
        icon: Icons.close_rounded,
        label: MissionContentData.benchCancelLabel,
        semantics: MissionContentData.benchCancelLabel,
        onPressed: onCancel,
      ));
    } else if (cable != null) {
      children.add(_CableChip(
        cable: cable,
        selected: true,
        enabled: enabled,
        focused: false,
        onTap: () => onSelectCable(cable),
        onDragChanged: onDragChanged,
        onDropMissed: onDropMissed,
      ));
      for (final header in model.headers) {
        children.add(_TrayButton(
          key: ValueKey('bench-header-chip-${header.id}'),
          icon: Icons.power_outlined,
          label: header.label,
          semantics: MissionContentData.benchHeaderSemantics(header.label),
          emphasised: !assessment && compatible.contains(header.id),
          onPressed: enabled ? () => onTapHeader(header.id) : null,
        ));
      }
      children.add(_TrayButton(
        key: const ValueKey('bench-cancel'),
        icon: Icons.close_rounded,
        label: MissionContentData.benchCancelLabel,
        semantics: MissionContentData.benchCancelLabel,
        onPressed: onCancel,
      ));
    } else {
      for (final object in model.inspectables) {
        children.add(_TrayButton(
          key: ValueKey('bench-inspect-chip-${object.id}'),
          icon: object.inspected
              ? Icons.check_circle_outline
              : Icons.search_rounded,
          label: object.label,
          semantics:
              MissionContentData.benchInspectSemantics(object.label, object.inspected),
          emphasised: focus.contains(object.id),
          onPressed: enabled ? () => onInspect(object) : null,
        ));
      }
      for (final part in model.parts) {
        children.add(_PartChip(
          part: part,
          turns: turnsFor(part),
          selected: false,
          enabled: enabled,
          focused: focus.contains(part.id),
          reducedMotion: reducedMotion,
          onTap: () => onSelectPart(part),
          onDragChanged: onDragChanged,
          onDropMissed: onDropMissed,
        ));
      }
      for (final cable in model.cables) {
        children.add(_CableChip(
          cable: cable,
          selected: false,
          enabled: enabled,
          focused: focus.contains(cable.id),
          onTap: () => onSelectCable(cable),
          onDragChanged: onDragChanged,
          onDropMissed: onDropMissed,
        ));
      }
      for (final operation in model.operations) {
        children.add(_TrayButton(
          key: ValueKey('bench-operation-${operation.id}'),
          icon: operation.done ? Icons.task_alt_rounded : _operationIcon(operation.id),
          label: operation.label,
          semantics: MissionContentData.benchOperationSemantics(
              operation.label, enabled && operation.enabled),
          emphasised: focus.contains(operation.id),
          onPressed:
              enabled && operation.enabled ? () => onOperate(operation) : null,
        ));
      }
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Material(
      color: AppTheme.cardWhite,
      child: Container(
        key: const ValueKey('assembly-bench-tray'),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.borderLight))),
        height: 64 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
        // A short, fully built row: every part stays reachable for drag,
        // keyboard and screen-reader focus.
        child: SingleChildScrollView(
          key: const ValueKey('assembly-bench-tray-scroll'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            for (final child in children)
              Padding(padding: const EdgeInsets.only(right: 6), child: child),
          ]),
        ),
      ),
    );
  }

  static IconData _operationIcon(String id) => switch (id) {
        'wear_wrist_strap' || 'ground_wrist_strap' => Icons.back_hand_outlined,
        'pick_screwdriver' ||
        'fasten_psu' ||
        'fasten_motherboard' ||
        'fasten_drive' =>
          Icons.construction_outlined,
        'apply_thermal_compound' => Icons.opacity_outlined,
        _ => Icons.lock_open_rounded,
      };
}

class _TrayButton extends StatelessWidget {
  const _TrayButton({
    super.key,
    required this.icon,
    required this.label,
    required this.semantics,
    required this.onPressed,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final String semantics;
  final VoidCallback? onPressed;
  final bool emphasised;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onPressed != null,
        label: semantics,
        excludeSemantics: true,
        // The child button's own semantics are excluded for the clearer
        // label, so the wrapper carries the tap a screen reader sends.
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: OutlinedButton.icon(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: emphasised ? AppTheme.softBlueAccent : null,
              side: BorderSide(
                  color: emphasised ? AppTheme.primaryBlue : AppTheme.borderMedium,
                  width: emphasised ? 2 : 1),
            ),
            // Practice emphasis (compatible slot or guided step) is also an
            // icon change, so it never relies on colour alone.
            icon: Icon(emphasised ? Icons.add_task_rounded : icon, size: 18),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
}

class _PartChip extends StatelessWidget {
  const _PartChip({
    required this.part,
    required this.turns,
    required this.selected,
    required this.enabled,
    required this.focused,
    required this.reducedMotion,
    required this.onTap,
    required this.onDragChanged,
    required this.onDropMissed,
    this.onDoubleTap,
  });

  final BenchPart part;
  final int turns;
  final bool selected;
  final bool enabled;
  final bool focused;
  final bool reducedMotion;
  final VoidCallback onTap;
  final ValueChanged<BenchDrag?> onDragChanged;
  final VoidCallback onDropMissed;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final image = _PartImage(
      id: part.id,
      asset: part.asset,
      turns: turns,
      reducedMotion: reducedMotion,
      size: 40,
    );
    final chip = Container(
      constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? AppTheme.softBlueAccent : AppTheme.surfaceMuted,
        borderRadius: AppTheme.radiusSm,
        border: Border.all(
          color: selected || focused ? AppTheme.primaryBlue : AppTheme.borderLight,
          width: selected || focused ? 2 : 1,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          image,
          if (part.placed)
            const Positioned(
              right: -4,
              top: -4,
              child: Icon(Icons.check_circle,
                  size: 16, color: AppTheme.accentGreen),
            ),
        ]),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Text(part.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.labelSmall),
        ),
      ]),
    );
    final drag = BenchDrag('part', part.id);
    final draggable = !part.placed && enabled
        ? Draggable<BenchDrag>(
            data: drag,
            maxSimultaneousDrags: 1,
            // The bench is above the tray: only a move up picks the part up,
            // so a sideways swipe on a tile scrolls the tray (a phone shows
            // only two or three tiles at a time).
            affinity: Axis.vertical,
            onDragStarted: () => onDragChanged(drag),
            onDragEnd: (_) => onDragChanged(null),
            onDraggableCanceled: (_, __) => onDropMissed(),
            feedback: Material(
              type: MaterialType.transparency,
              child: SizedBox(
                key: ValueKey('bench-drag-ghost-${part.id}'),
                width: 96,
                height: 96,
                child: _PartImage(
                    id: part.id,
                    asset: part.asset,
                    turns: turns,
                    reducedMotion: true,
                    size: 96),
              ),
            ),
            childWhenDragging: Opacity(opacity: .4, child: chip),
            child: chip,
          )
        : chip;
    final position = benchMarkerDescription(part.id, turns, angle: false);
    final label = MissionContentData.benchPartSemantics(part.label, part.placed);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      // The tile names where its marker is now (never an angle or a fit).
      label: position == null || part.placed
          ? label
          : MissionContentData.benchPartMarkerSemantics(label, position),
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: GestureDetector(
        key: ValueKey('bench-part-${part.id}'),
        onTap: enabled ? onTap : null,
        onDoubleTap: enabled ? onDoubleTap : null,
        child: draggable,
      ),
    );
  }
}

/// A part photograph turned by [turns] quarter turns (animated 200 ms). A
/// keyed part carries its orientation marker inside the rotation, so the
/// marker turns with the part wherever the part is shown. Without [size]
/// the square photograph fills the largest square that fits.
class _PartImage extends StatelessWidget {
  const _PartImage({
    required this.id,
    required this.asset,
    required this.turns,
    required this.reducedMotion,
    this.size,
  });

  final String id;
  final String? asset;
  final int turns;
  final bool reducedMotion;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final size = this.size;
    if (size == null) {
      return Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
              builder: (context, box) => _turned(box.biggest.shortestSide)),
        ),
      );
    }
    return SizedBox(width: size, height: size, child: _turned(size));
  }

  Widget _turned(double extent) {
    final marker = AssemblyBenchLayout.markers[id];
    Widget photo = asset == null
        ? const Icon(Icons.memory_outlined)
        : Image(image: AssetImage(asset!), fit: BoxFit.contain);
    if (marker != null && marker.baseTurns != 0) {
      photo = RotatedBox(quarterTurns: marker.baseTurns, child: photo);
    }
    return AnimatedRotation(
      key: ValueKey('bench-rotation-$id'),
      turns: turns / 4,
      duration:
          reducedMotion ? Duration.zero : AppTheme.simulationTransitionDuration,
      child: marker == null
          ? photo
          : Stack(fit: StackFit.expand, children: [
              photo,
              if (marker.kind == BenchMarkerKind.fan)
                const CustomPaint(painter: BenchFanRingPainter()),
              Positioned(
                left: marker.box.left * extent,
                top: marker.box.top * extent,
                width: marker.box.width * extent,
                height: marker.box.height * extent,
                child: CustomPaint(
                  key: ValueKey('bench-marker-$id'),
                  painter: BenchMarkerPainter(marker.kind),
                ),
              ),
            ]),
    );
  }
}

/// Where a keyed part's marker is at [turns] quarter turns from 0°, e.g.
/// "Triangle: top-left · 90°". It describes the part, never the fit. Without
/// [angle] (assessment) only the position is given: every keyed part seats
/// at 0°, so the angle alone would tell the learner when to stop turning.
String? benchMarkerDescription(String partId, int turns, {bool angle = true}) {
  final marker = AssemblyBenchLayout.markers[partId];
  if (marker == null) return null;
  final index = turns % 4;
  final (name, positions) = switch (marker.kind) {
    BenchMarkerKind.triangle => (
        MissionContentData.benchMarkerTriangle,
        MissionContentData.benchMarkerCorners
      ),
    BenchMarkerKind.notch => (
        MissionContentData.benchMarkerNotch,
        MissionContentData.benchMarkerEdges
      ),
    BenchMarkerKind.fan => (
        MissionContentData.benchMarkerFan,
        MissionContentData.benchMarkerFacings
      ),
  };
  return angle
      ? MissionContentData.benchMarkerDescription(
          name, positions[index], index * 90)
      : MissionContentData.benchMarkerPosition(name, positions[index]);
}

/// Larger view of the keyed part in hand: its photograph and marker at the
/// current rotation, and where the marker is now. Announced on rotation. A
/// short bench gets a compact row, so it stays clear of the note below.
class _PartPreview extends StatelessWidget {
  const _PartPreview({
    required this.part,
    required this.turns,
    required this.reducedMotion,
    required this.compact,
    required this.assessment,
  });

  final BenchPart part;
  final int turns;
  final bool reducedMotion;
  final bool compact;
  final bool assessment;

  @override
  Widget build(BuildContext context) {
    final description =
        benchMarkerDescription(part.id, turns, angle: !assessment) ?? '';
    final image = _PartImage(
      id: part.id,
      asset: part.asset,
      turns: turns,
      reducedMotion: reducedMotion,
      size: compact ? 48 : 96,
    );
    final text = Text(
      description,
      key: const ValueKey('bench-part-preview-description'),
      textAlign: compact ? TextAlign.start : TextAlign.center,
      maxLines: compact ? 2 : 3,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.labelSmall.copyWith(color: AppTheme.navy),
    );
    return Semantics(
      liveRegion: true,
      label: MissionContentData.benchPreviewSemantics(part.label, description),
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('bench-part-preview'),
        width: compact ? null : 120,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.cardWhite,
          borderRadius: AppTheme.radiusSm,
          border: Border.all(color: AppTheme.borderMedium),
        ),
        child: compact
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                image,
                const SizedBox(width: 8),
                ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 112),
                    child: text),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                image,
                const SizedBox(height: 4),
                text,
              ]),
      ),
    );
  }
}

/// A small name plate on the bench canvas, scaled with the camera like the
/// silkscreen; it never takes a tap from the hotspot beside it.
class _SceneLabel extends StatelessWidget {
  const _SceneLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.cardWhite,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderMedium, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.navy),
                ),
              ),
            ),
          ),
        ),
      );
}

class _CableChip extends StatelessWidget {
  const _CableChip({
    required this.cable,
    required this.selected,
    required this.enabled,
    required this.focused,
    required this.onTap,
    required this.onDragChanged,
    required this.onDropMissed,
  });

  final BenchCable cable;
  final bool selected;
  final bool enabled;
  final bool focused;
  final VoidCallback onTap;
  final ValueChanged<BenchDrag?> onDragChanged;
  final VoidCallback onDropMissed;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? AppTheme.softBlueAccent : AppTheme.surfaceMuted,
        borderRadius: AppTheme.radiusSm,
        border: Border.all(
          color: selected || focused ? AppTheme.primaryBlue : AppTheme.borderLight,
          width: selected || focused ? 2 : 1,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 40,
          height: 40,
          child: cable.asset == null
              ? const Icon(Icons.cable_rounded)
              : Image(image: AssetImage(cable.asset!), fit: BoxFit.contain),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(cable.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.labelSmall),
        ),
        if (cable.linkedTo != null)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.link_rounded, size: 16, color: AppTheme.accentGreen),
          ),
      ]),
    );
    final header = cable.linkedTo;
    final drag = BenchDrag('cable', cable.id);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: MissionContentData.benchCableSemantics(cable.label, header),
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: GestureDetector(
        key: ValueKey('bench-cable-${cable.id}'),
        onTap: enabled ? onTap : null,
        child: enabled
            ? Draggable<BenchDrag>(
                data: drag,
                maxSimultaneousDrags: 1,
                // Like a part tile: up drags, sideways scrolls the tray.
                affinity: Axis.vertical,
                onDragStarted: () => onDragChanged(drag),
                onDragEnd: (_) => onDragChanged(null),
                onDraggableCanceled: (_, __) => onDropMissed(),
                feedback: Material(
                  type: MaterialType.transparency,
                  child: SizedBox(
                    key: ValueKey('bench-drag-ghost-${cable.id}'),
                    width: 72,
                    height: 72,
                    child: cable.asset == null
                        ? const Icon(Icons.cable_rounded, size: 48)
                        : Image(
                            image: AssetImage(cable.asset!),
                            fit: BoxFit.contain),
                  ),
                ),
                childWhenDragging: Opacity(opacity: .4, child: chip),
                child: chip,
              )
            : chip,
      ),
    );
  }
}
