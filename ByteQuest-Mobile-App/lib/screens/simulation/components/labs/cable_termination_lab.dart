import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/mission_content_data.dart';
import '../../runtime/mission_equipment_simulator.dart';
import '../../runtime/mission_runtime_models.dart';
import '../tool_tray.dart' show MissionActionCallback;

/// COC2 M2 phase 2 as an RJ45 termination bench.
///
/// The learner inserts the eight untwisted conductors into the plug's pin
/// channels and crimps. The crimp records exactly what the standard reorder
/// list records: one confirmed `sequence_reordered` whose order is the
/// conductor in pins 1–8. Assessment mode never shows the colour order.
class CableTerminationLab extends StatefulWidget {
  const CableTerminationLab({
    super.key,
    required this.phase,
    required this.state,
    required this.onAction,
    required this.enabled,
    this.onDraftChanged,
  });

  final MissionPhaseDefinition phase;
  final MissionRuntimeState state;
  final MissionActionCallback onAction;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>>? onDraftChanged;

  @override
  State<CableTerminationLab> createState() => _CableTerminationLabState();
}

/// Conductor colours: (insulation, stripe) — white conductors carry the
/// stripe of their pair colour.
const _conductorColors = <String, (Color, Color?)>{
  'orange': (Color(0xFFEF7D1A), null),
  'green': (Color(0xFF2E9B4F), null),
  'blue': (Color(0xFF2563EB), null),
  'brown': (Color(0xFF7B4A24), null),
  'white_orange': (Color(0xFFF7F7F2), Color(0xFFEF7D1A)),
  'white_green': (Color(0xFFF7F7F2), Color(0xFF2E9B4F)),
  'white_blue': (Color(0xFFF7F7F2), Color(0xFF2563EB)),
  'white_brown': (Color(0xFFF7F7F2), Color(0xFF7B4A24)),
};

/// The standard pin order, shown in practice mode only.
const _t568b = [
  'white_orange',
  'orange',
  'white_green',
  'blue',
  'white_blue',
  'green',
  'white_brown',
  'brown',
];

class _CableTerminationLabState extends State<CableTerminationLab> {
  late List<String?> _pins;
  String? _selected;
  bool _crimped = false;
  String _inputMethod = 'tap';

  List<Map<String, dynamic>> get _conductors =>
      MissionEquipmentSimulator.maps(widget.phase.presentation['items']);

  int get _pinCount => _conductors.length;

  String _label(String id) => _conductors.firstWhere((c) => c['id'] == id,
      orElse: () => {'label': id})['label'] as String;

  Map<String, dynamic> get _recorded =>
      MissionEquipmentSimulator.map(MissionEquipmentSimulator.map(
          widget.state.equipmentState['phases'])[widget.phase.id]);

  bool get _assessment => widget.state.mode == MissionRuntimeMode.assessment;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(covariant CableTerminationLab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase.id != widget.phase.id ||
        oldWidget.state.mode != widget.state.mode ||
        oldWidget.state.assessmentAttemptId !=
            widget.state.assessmentAttemptId) {
      _restore();
    }
  }

  int get _evidenceCount =>
      widget.state.acceptedEvidenceIds.length +
      widget.state.pendingEvidence.length;
  List<String> get _recordedOrder =>
      MissionEquipmentSimulator.strings(_recorded['order']);

  void _restore() {
    final order = _recordedOrder;
    _selected = null;
    _inputMethod = 'tap';
    _crimped = order.length == _pinCount;
    _pins = _crimped ? List.of(order) : List<String?>.filled(_pinCount, null);
    final draft = widget.state.workbenchDraft;
    final pins = draft['pins'];
    final selected = draft['selected'];
    final method = draft['method'];
    final ids = _conductors.map((c) => c['id']).toSet();
    // A fresh plug must not hide a later crimp, even one with the same eight wires.
    if (draft['phase'] != widget.phase.id ||
        draft['base'] != order.join(',') ||
        (_crimped && draft['baseCount'] != _evidenceCount) ||
        pins is! List ||
        pins.length != _pinCount ||
        !pins.every((p) => p == null || ids.contains(p)) ||
        pins.whereType<String>().toSet().length !=
            pins.whereType<String>().length ||
        (selected != null &&
            (!ids.contains(selected) || pins.contains(selected))) ||
        (method != 'drag' && method != 'tap')) {
      return;
    }
    _crimped = false;
    _pins = List<String?>.from(pins);
    _selected = selected as String?;
    _inputMethod = method as String;
  }

  void _edit(VoidCallback change) {
    setState(change);
    widget.onDraftChanged?.call({
      'phase': widget.phase.id,
      'base': _recordedOrder.join(','),
      'baseCount': _evidenceCount,
      'pins': List<String?>.of(_pins),
      'selected': _selected,
      'method': _inputMethod,
    });
  }

  bool get _interactive => widget.enabled && !_crimped;

  void _insert(String conductor, int pin, String method) {
    if (!_interactive || !_conductors.any((c) => c['id'] == conductor)) return;
    _edit(() {
      final from = _pins.indexOf(conductor);
      if (from >= 0) _pins[from] = null;
      _pins[pin] = conductor;
      _selected = null;
      _inputMethod = method;
    });
  }

  void _tapPin(int pin) {
    if (!_interactive) return;
    final selected = _selected;
    if (selected != null) {
      _insert(selected, pin, 'tap');
    } else if (_pins[pin] != null) {
      _edit(() => _pins[pin] = null);
    }
  }

  void _tapConductor(String id) {
    if (!_interactive) return;
    _edit(() => _selected = _selected == id ? null : id);
  }

  void _crimp() {
    if (!_interactive || _pins.any((pin) => pin == null)) return;
    setState(() => _crimped = true);
    unawaited(widget.onAction('sequence_reordered', widget.phase.id, {
      'order': List<String>.from(_pins.whereType<String>()),
      'input_method': _inputMethod,
      'confirmed': true,
    }));
  }

  void _reterminate() {
    if (!widget.enabled) return;
    _edit(() {
      _pins = List<String?>.filled(_pinCount, null);
      _crimped = false;
      _selected = null;
      _inputMethod = 'tap';
    });
  }

  @override
  Widget build(BuildContext context) {
    final placed = _pins.whereType<String>().toSet();
    final loose = [
      for (final c in _conductors)
        if (!placed.contains(c['id'])) c['id'] as String,
    ];
    final allFilled = _pins.every((pin) => pin != null);
    final recordedOrder = MissionEquipmentSimulator.strings(_recorded['order']);
    final recordedHere = _crimped &&
        recordedOrder.length == _pinCount &&
        List.generate(_pinCount, (i) => recordedOrder[i] == _pins[i])
            .every((same) => same);
    final valid = _recorded['sequence_valid'] == true;

    return KeyedSubtree(
      key: const ValueKey('mission-lab'),
      child: Semantics(
        container: true,
        label: MissionContentData.labCableTitle,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.cable_rounded, color: AppTheme.deepBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(MissionContentData.labCableTitle,
                        style: AppTheme.labelLarge),
                  ),
                  ExcludeSemantics(
                    child: Image.asset(
                      'assets/COC2/Mission 1/Crimping Tool.png',
                      height: 40,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                _ConnectorView(
                  pins: _pins,
                  labelFor: _label,
                  crimped: _crimped,
                  enabled: _interactive,
                  onTapPin: _tapPin,
                  onDrop: (conductor, pin) => _insert(conductor, pin, 'drag'),
                ),
                const SizedBox(height: 12),
                Text(MissionContentData.labCableConductorsTitle,
                    style: AppTheme.labelLarge),
                const SizedBox(height: 6),
                _CableEnd(
                  conductors: loose,
                  labelFor: _label,
                  selected: _selected,
                  enabled: _interactive,
                  onTap: _tapConductor,
                ),
                const SizedBox(height: 8),
                if (!_crimped)
                  Text(MissionContentData.labCableInstruction,
                      style: AppTheme.bodySmall),
                if (!_assessment) ...[
                  const SizedBox(height: 8),
                  _ReferenceCard(labelFor: _label),
                ],
                const SizedBox(height: 10),
                if (!_crimped)
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('lab-cable-clear'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                        onPressed: _interactive && placed.isNotEmpty
                            ? _reterminate
                            : null,
                        child:
                            const Text(MissionContentData.labCableClearLabel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('lab-cable-crimp'),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                        onPressed: _interactive && allFilled ? _crimp : null,
                        icon: const Icon(Icons.compress_rounded),
                        label:
                            const Text(MissionContentData.labCableCrimpLabel),
                      ),
                    ),
                  ])
                else ...[
                  Semantics(
                    liveRegion: true,
                    child: _StatusLine(
                      valid: _assessment || !recordedHere ? null : valid,
                      text: !recordedHere || _assessment
                          ? MissionContentData.labCableCrimped
                          : valid
                              ? MissionContentData.labCableCrimpedPractice
                              : MissionContentData.labCableMiswiredPractice,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('lab-cable-reterminate'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: widget.enabled ? _reterminate : null,
                    icon: const Icon(Icons.content_cut_rounded),
                    label:
                        const Text(MissionContentData.labCableReterminateLabel),
                  ),
                ],
                if (!_crimped && !allFilled && placed.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(MissionContentData.labCableFillAll,
                      style: AppTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectorView extends StatelessWidget {
  const _ConnectorView({
    required this.pins,
    required this.labelFor,
    required this.crimped,
    required this.enabled,
    required this.onTapPin,
    required this.onDrop,
  });

  final List<String?> pins;
  final String Function(String id) labelFor;
  final bool crimped;
  final bool enabled;
  final ValueChanged<int> onTapPin;
  final void Function(String conductor, int pin) onDrop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // The plug's outline is painted over its edge, so the eight channels
      // get the full width: 48 dp each from a 384 dp wide lab (a 411 dp
      // phone). Narrower screens show the plug on its side, one channel per
      // row, so every channel keeps a 48 dp target and none hides off screen.
      final channel = constraints.maxWidth / pins.length;
      final sideways = channel < 48;
      Widget channelFor(int i) => _PinChannel(
            pin: i + 1,
            conductor: pins[i],
            label: pins[i] == null ? null : labelFor(pins[i]!),
            crimped: crimped,
            enabled: enabled,
            sideways: sideways,
            onTap: () => onTapPin(i),
            onDrop: (conductor) => onDrop(conductor, i),
          );
      final radius = BorderRadius.circular(10);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            sideways
                ? MissionContentData.labCableConnectorCaptionSide
                : MissionContentData.labCableConnectorCaption,
            style: AppTheme.bodySmall),
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('lab-cable-plug'),
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          decoration: BoxDecoration(
              color: const Color(0x33B6D8FF), borderRadius: radius),
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF8FB4E6), width: 2),
            borderRadius: radius,
          ),
          child: sideways
              ? Column(children: [
                  for (var i = 0; i < pins.length; i++) channelFor(i),
                ])
              : Column(children: [
                  Row(children: [
                    for (var i = 0; i < pins.length; i++)
                      SizedBox(width: channel, child: channelFor(i)),
                  ]),
                  const SizedBox(height: 6),
                  // The latch clip sits under the plug in this front view.
                  Container(
                    height: 10,
                    width: channel * 3,
                    decoration: BoxDecoration(
                      color: const Color(0x668FB4E6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ]),
        ),
      ]);
    });
  }
}

class _PinChannel extends StatelessWidget {
  const _PinChannel({
    required this.pin,
    required this.conductor,
    required this.label,
    required this.crimped,
    required this.enabled,
    required this.sideways,
    required this.onTap,
    required this.onDrop,
  });

  final int pin;
  final String? conductor;
  final String? label;
  final bool crimped;
  final bool enabled;

  /// One row per channel (the plug on its side) instead of a column.
  final bool sideways;
  final VoidCallback onTap;
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => enabled,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        // Gold contact blade, pressed down after the crimp.
        final blade = Container(
          width: sideways ? (crimped ? 10 : 6) : null,
          height: sideways ? null : (crimped ? 10 : 6),
          margin: sideways
              ? const EdgeInsets.symmetric(vertical: 9)
              : const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFD4AF37),
            borderRadius: BorderRadius.circular(2),
          ),
        );
        Widget wire(double length, double width) => sideways
            ? RotatedBox(
                quarterTurns: 3,
                child: _Wire(id: conductor!, length: length, width: width))
            : _Wire(id: conductor!, length: length, width: width);
        final channel = Container(
          height: sideways ? 40 : 92,
          margin: sideways
              ? const EdgeInsets.symmetric(vertical: 4)
              : const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: hovering
                ? AppTheme.primaryBlue.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: hovering ? AppTheme.primaryBlue : const Color(0xFFB8C7DD),
            ),
          ),
          alignment: sideways ? Alignment.centerLeft : Alignment.bottomCenter,
          child: conductor == null
              ? null
              : Draggable<String>(
                  data: conductor,
                  maxSimultaneousDrags: enabled ? 1 : 0,
                  feedback: _Wire(id: conductor!, length: 80, width: 16),
                  childWhenDragging: const SizedBox.shrink(),
                  child: wire(sideways ? 140 : 86, 14),
                ),
        );
        final number = Text('$pin', style: AppTheme.labelLarge);
        final body = sideways
            ? SizedBox(
                height: 48,
                child: Row(children: [
                  SizedBox(width: 28, child: Center(child: number)),
                  Expanded(child: channel),
                  const SizedBox(width: 4),
                  blade,
                ]),
              )
            : Column(mainAxisSize: MainAxisSize.min, children: [
                blade,
                const SizedBox(height: 4),
                channel,
                const SizedBox(height: 4),
                number,
              ]);
        return Semantics(
          button: true,
          enabled: enabled,
          label: MissionContentData.labCablePinSemantics(pin, label),
          child: InkWell(
            key: ValueKey('lab-cable-pin-$pin'),
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: body,
            ),
          ),
        );
      },
    );
  }
}

class _CableEnd extends StatelessWidget {
  const _CableEnd({
    required this.conductors,
    required this.labelFor,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final List<String> conductors;
  final String Function(String id) labelFor;
  final String? selected;
  final bool enabled;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Stripped outer jacket of the cable the conductors come from.
      ExcludeSemantics(
        child: Container(
          width: 26,
          height: 64,
          margin: const EdgeInsets.only(right: 8, top: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF9AA4B2),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      Expanded(
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final id in conductors)
            Semantics(
              button: true,
              selected: selected == id,
              enabled: enabled,
              label: MissionContentData.labCableConductorSemantics(
                  labelFor(id), selected == id),
              child: Draggable<String>(
                data: id,
                maxSimultaneousDrags: enabled ? 1 : 0,
                feedback: Material(
                  color: Colors.transparent,
                  child: _Wire(id: id, length: 80, width: 16),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: _ConductorChip(
                      id: id, label: labelFor(id), selected: false),
                ),
                child: InkWell(
                  key: ValueKey('lab-cable-conductor-$id'),
                  onTap: enabled ? () => onTap(id) : null,
                  borderRadius: BorderRadius.circular(10),
                  child: _ConductorChip(
                      id: id, label: labelFor(id), selected: selected == id),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}

class _ConductorChip extends StatelessWidget {
  const _ConductorChip(
      {required this.id, required this.label, required this.selected});
  final String id;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppTheme.softBlueAccent : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppTheme.primaryBlue : const Color(0xFFD5DCE8),
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        RotatedBox(
            quarterTurns: 3, child: _Wire(id: id, length: 34, width: 12)),
        const SizedBox(width: 8),
        Text(label, style: AppTheme.bodySmall),
      ]),
    );
  }
}

/// One insulated conductor drawn vertically: solid colour, or white with
/// the pair colour as a spiral stripe.
class _Wire extends StatelessWidget {
  const _Wire({required this.id, required this.length, required this.width});
  final String id;
  final double length;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = _conductorColors[id] ?? (Colors.grey, null);
    return CustomPaint(
      size: Size(width, length),
      painter: _WirePainter(colors.$1, colors.$2),
    );
  }
}

class _WirePainter extends CustomPainter {
  _WirePainter(this.base, this.stripe);
  final Color base;
  final Color? stripe;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.width / 2));
    canvas.drawRRect(rect, Paint()..color = base);
    if (stripe != null) {
      canvas.save();
      canvas.clipRRect(rect);
      final paint = Paint()
        ..color = stripe!
        ..strokeWidth = size.width * 0.45;
      for (var y = -size.width;
          y < size.height + size.width;
          y += size.width * 1.6) {
        canvas.drawLine(
            Offset(0, y + size.width), Offset(size.width, y), paint);
      }
      canvas.restore();
    }
    canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x55000000));
  }

  @override
  bool shouldRepaint(covariant _WirePainter old) =>
      old.base != base || old.stripe != stripe;
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.labelFor});
  final String Function(String id) labelFor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: const ValueKey('lab-cable-reference'),
        title: const Text(MissionContentData.labCableReferenceTitle),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Wrap(spacing: 10, runSpacing: 6, children: [
            for (var i = 0; i < _t568b.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${i + 1}', style: AppTheme.labelLarge),
                const SizedBox(width: 4),
                RotatedBox(
                    quarterTurns: 3,
                    child: _Wire(id: _t568b[i], length: 24, width: 10)),
                const SizedBox(width: 4),
                Text(labelFor(_t568b[i]), style: AppTheme.bodySmall),
              ]),
          ]),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.valid, required this.text});
  final bool? valid;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (valid) {
      true => (AppTheme.successGreen, Icons.check_circle_outline),
      false => (AppTheme.errorRed, Icons.error_outline),
      null => (AppTheme.deepBlue, Icons.receipt_long_outlined),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: AppTheme.bodySmall)),
      ]),
    );
  }
}
