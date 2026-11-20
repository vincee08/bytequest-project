import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/mission_content_data.dart';
import '../../runtime/mission_equipment_simulator.dart';
import '../../runtime/mission_runtime_models.dart';
import '../tool_tray.dart' show MissionActionCallback;

/// COC4 M4 phases 1, 2 and 4 on a workstation service bench.
///
/// Physical work on the open case records exactly the actions of the
/// standard panels:
/// - phase 1: the bracket-screw `tool_attempted`, the contingency
///   `equipment_operation`, and one confirmed `sequence_reordered` with the
///   steps (isolate, remove, inspect) in the order they were performed;
/// - phase 2: `placement_attempted` with the adapter's orientation;
/// - phase 4: one confirmed `sequence_reordered` (seat, fasten, configure,
///   restore) in the order they were performed.
/// Steps done in an unsafe order are recorded as performed, never corrected.
class PcieReplacementLab extends StatefulWidget {
  const PcieReplacementLab({
    super.key,
    required this.phase,
    required this.state,
    required this.onAction,
    required this.enabled,
  });

  final MissionPhaseDefinition phase;
  final MissionRuntimeState state;
  final MissionActionCallback onAction;
  final bool enabled;

  @override
  State<PcieReplacementLab> createState() => _PcieReplacementLabState();
}

enum _Stage { removal, install, closeOut }

const _motherboardAsset = 'assets/COC1/Mission 2/motherboard.png';
const _adapterAsset = 'assets/COC2/Mission 1/NIC.png';
const _powerAsset = 'assets/COC1/Mission 1/power_cable.png';
const _strapAsset = 'assets/COC1/Mission 1/anti_static_wrist_strap.png';
const _toolAssets = {
  'esd_driver': 'assets/COC1/Mission 1/screwdriver.png',
  'wire_cutter': 'assets/COC2/Mission 1/Wire Stripper.png',
};

/// Expansion slot on the motherboard photo (fractions of its 500 px square):
/// the full-length black PCIe slot below the graphics slot.
const _slot = Rect.fromLTWH(0.256, 0.722, 0.268, 0.024);

class _PcieReplacementLabState extends State<PcieReplacementLab> {
  // Phase 1.
  bool _powerConnected = true;
  bool _strapOn = false;
  bool _cardOut = false;
  bool _inspected = false;
  String? _tool;
  // Phase 2.
  bool _aligned = false;
  bool _adapterSelected = false;
  // Phase 4.
  bool _latched = false;
  bool _fastened = false;
  bool _configured = false;
  bool _panelOn = false;
  bool _powerBack = false;
  String? _toolMessage;

  final List<String> _steps = [];
  bool _submitted = false;

  _Stage get _stage => switch (widget.phase.id.split('_').last) {
        'p1' => _Stage.removal,
        'p2' => _Stage.install,
        _ => _Stage.closeOut,
      };

  Map<String, dynamic> get _presentation => widget.phase.presentation;
  Map<String, dynamic> get _equipment =>
      MissionEquipmentSimulator.map(_presentation['equipment']);
  List<Map<String, dynamic>> get _items =>
      MissionEquipmentSimulator.maps(_presentation['items']);

  Map<String, dynamic> get _recorded =>
      MissionEquipmentSimulator.map(MissionEquipmentSimulator.map(
          widget.state.equipmentState['phases'])[widget.phase.id]);

  bool get _assessment => widget.state.mode == MissionRuntimeMode.assessment;

  String get _screwTarget =>
      MissionEquipmentSimulator.maps(_equipment['targets']).firstOrNull?['id']
          as String? ??
      'retaining_screw';

  bool get _screwOut => widget.state.toolApplications[_screwTarget] != null;

  bool get _contingencyReady =>
      widget.state.equipmentState['contingency_ready'] == true;

  Map<String, dynamic> get _adapter => _items.firstOrNull ?? const {};
  Map<String, dynamic> get _slotDestination =>
      MissionEquipmentSimulator.maps(_presentation['destinations'])
          .firstOrNull ??
      const {};

  bool get _adapterInstalled =>
      _adapter['id'] != null &&
      widget.state.placements[_adapter['id']] == _slotDestination['id'];

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(covariant PcieReplacementLab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase.id != widget.phase.id) _restore();
  }

  /// A confirmed procedure survives pause and resume. Every recorded step is
  /// shown as performed, whatever its order, so a resumed assessment never
  /// hints at whether the order was safe.
  void _restore() {
    _steps.clear();
    _submitted = false;
    _tool = null;
    _toolMessage = null;
    _adapterSelected = false;
    final order = MissionEquipmentSimulator.strings(_recorded['order']);
    final performed = order.length == _items.length;
    if (performed) {
      _steps.addAll(order);
      _submitted = true;
    }
    switch (_stage) {
      case _Stage.removal:
        _powerConnected = !performed;
        _strapOn = _cardOut = _inspected = performed;
      case _Stage.install:
        _aligned = _adapterInstalled;
      case _Stage.closeOut:
        _latched = _fastened = _configured = _panelOn = _powerBack = performed;
    }
  }

  bool get _interactive => widget.enabled && !_submitted;

  void _done(String step) {
    if (_steps.contains(step) || !_items.any((item) => item['id'] == step)) {
      return;
    }
    _steps.add(step);
    if (_steps.length == _items.length) {
      _submitted = true;
      unawaited(widget.onAction('sequence_reordered', widget.phase.id, {
        'order': List<String>.from(_steps),
        'input_method': 'tap',
        'confirmed': true,
      }));
    }
  }

  void _restart() {
    if (!widget.enabled) return;
    setState(() {
      _steps.clear();
      _submitted = false;
      _toolMessage = null;
      if (_stage == _Stage.removal) {
        _powerConnected = true;
        _strapOn = false;
        _cardOut = false;
        _inspected = false;
      } else {
        _latched = _fastened = _configured = _panelOn = _powerBack = false;
      }
    });
  }

  // Phase 1 ------------------------------------------------------------------

  void _unplug() {
    if (!_interactive || !_powerConnected) return;
    setState(() {
      _powerConnected = false;
      if (_strapOn) _done('isolate');
    });
  }

  void _wearStrap() {
    if (!_interactive || _strapOn) return;
    setState(() {
      _strapOn = true;
      if (!_powerConnected) _done('isolate');
    });
  }

  void _useToolOnScrew() {
    if (!widget.enabled) return;
    final tool = _tool;
    if (tool == null) {
      setState(() => _toolMessage = MissionContentData.labPcieToolHint);
      return;
    }
    if (_stage == _Stage.removal) {
      if (_screwOut || _cardOut) return;
      setState(() => _toolMessage = null);
      unawaited(widget.onAction('tool_attempted', _screwTarget, {
        'tool_id': tool,
        'input_method': 'tap',
      }));
    } else if (_stage == _Stage.closeOut && _latched && !_fastened) {
      // Phase 4 records only its step order; the tool is part of the step.
      setState(() {
        if (tool == 'esd_driver') {
          _fastened = true;
          _toolMessage = null;
          _done('fasten');
        } else {
          _toolMessage = MissionContentData.incompatibleToolFeedback;
        }
      });
    }
  }

  void _liftCard() {
    if (!_interactive || _cardOut || !_screwOut) return;
    setState(() {
      _cardOut = true;
      _done('remove');
    });
  }

  void _inspect() {
    if (!_interactive || _inspected) return;
    setState(() {
      _inspected = true;
      _done('inspect');
    });
  }

  void _recordContingency() {
    if (!widget.enabled || _contingencyReady) return;
    final operation =
        MissionEquipmentSimulator.maps(_equipment['operations']).firstOrNull;
    if (operation == null) return;
    unawaited(widget.onAction('equipment_operation', operation['id'] as String,
        const {'input_method': 'tap'}));
  }

  // Phase 2 ------------------------------------------------------------------

  void _placeAdapter(String method) {
    if (!widget.enabled || _adapterInstalled) return;
    final item = _adapter;
    final destination = _slotDestination;
    if (item['id'] == null || destination['id'] == null) return;
    final orientations =
        MissionEquipmentSimulator.strings(item['orientations']);
    final seating = item['seating_orientation'] as String?;
    final other =
        orientations.firstWhere((o) => o != seating, orElse: () => 'rotated');
    final accepted = MissionEquipmentSimulator.strings(
            destination['socket_categories'] ??
                destination['accepted_categories'])
        .toSet();
    final compatible =
        accepted.isEmpty || accepted.contains(item['category'] as String?);
    setState(() => _adapterSelected = false);
    unawaited(
        widget.onAction('placement_attempted', destination['id'] as String, {
      'item_id': item['id'],
      'destination_id': destination['id'],
      'compatible': compatible,
      if (seating != null) 'orientation': _aligned ? seating : other,
      if (!compatible) 'feedback_id': 'placement_incompatible',
      'input_method': method,
    }));
  }

  // Phase 4 ------------------------------------------------------------------

  void _latch() {
    if (!_interactive || _latched) return;
    setState(() {
      _latched = true;
      _done('seat');
    });
  }

  void _configure() {
    if (!_interactive || _configured) return;
    setState(() {
      _configured = true;
      _done('configure');
    });
  }

  void _refitPanel() {
    if (!_interactive || _panelOn) return;
    setState(() {
      _panelOn = true;
      if (_powerBack) _done('restore');
    });
  }

  void _reconnectPower() {
    if (!_interactive || _powerBack) return;
    setState(() {
      _powerBack = true;
      if (_panelOn) _done('restore');
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 640 &&
          constraints.maxWidth > constraints.maxHeight;
      final interior = _Interior(
        stage: _stage,
        cardPresent: switch (_stage) {
          _Stage.removal => !_cardOut,
          _Stage.install => _adapterInstalled,
          _Stage.closeOut => true,
        },
        cardFailed: _stage == _Stage.removal,
        screwIn: switch (_stage) {
          _Stage.removal => !_screwOut,
          _Stage.install => false,
          _Stage.closeOut => _fastened,
        },
        screwActive: widget.enabled &&
            ((_stage == _Stage.removal && !_screwOut && !_cardOut) ||
                (_stage == _Stage.closeOut && _latched && !_fastened)),
        slotDroppable:
            _stage == _Stage.install && widget.enabled && !_adapterInstalled,
        panelOn: _stage == _Stage.closeOut && _panelOn,
        powerConnected: switch (_stage) {
          _Stage.removal => _powerConnected,
          _Stage.install => false,
          _Stage.closeOut => _powerBack,
        },
        strapOn: switch (_stage) {
          _Stage.removal => _strapOn,
          _Stage.install => true,
          _Stage.closeOut => !_powerBack,
        },
        onScrew: _useToolOnScrew,
        onSlotTap: _adapterSelected ? () => _placeAdapter('tap') : null,
        onAdapterDropped: () => _placeAdapter('drag'),
      );
      final controls = _controls();
      final content = wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: interior),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: controls),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              interior,
              const SizedBox(height: 12),
              controls,
            ]);
      return KeyedSubtree(
        key: const ValueKey('mission-lab'),
        child: Semantics(
          container: true,
          label: MissionContentData.labPcieTitle,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(child: content),
          ),
        ),
      );
    });
  }

  /// Step controls in the order the phase lists its steps - the order the
  /// standard reorder list starts from - so reading the bench top to bottom
  /// never spells out the safe order.
  List<Widget> _inListedOrder(Map<String, List<Widget>> groups) => [
        for (final item in _items)
          if (groups[item['id']] case final group?) ...[
            ...group,
            const SizedBox(height: 10),
          ],
      ];

  Widget _controls() {
    final children = <Widget>[];
    switch (_stage) {
      case _Stage.removal:
        children.addAll(_inListedOrder({
          'isolate': [
            Row(children: [
              Expanded(
                child: _BenchTile(
                  key: const ValueKey('lab-pcie-power'),
                  asset: _powerAsset,
                  status: _powerConnected
                      ? MissionContentData.labPciePowerConnected
                      : MissionContentData.labPciePowerIsolated,
                  actionLabel: MissionContentData.labPcieUnplugLabel,
                  done: !_powerConnected,
                  onPressed: _interactive && _powerConnected ? _unplug : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BenchTile(
                  key: const ValueKey('lab-pcie-strap'),
                  asset: _strapAsset,
                  status: _strapOn
                      ? MissionContentData.labPcieStrapOn
                      : MissionContentData.labPcieStrapOff,
                  actionLabel: MissionContentData.labPcieWearStrapLabel,
                  done: _strapOn,
                  onPressed: _interactive && !_strapOn ? _wearStrap : null,
                ),
              ),
            ]),
          ],
          'remove': [
            _toolRow(),
            const SizedBox(height: 8),
            _ActionButton(
              key: const ValueKey('lab-pcie-lift'),
              icon: Icons.upload_rounded,
              label: MissionContentData.labPcieRemoveCardLabel,
              done: _cardOut,
              onPressed:
                  _interactive && _screwOut && !_cardOut ? _liftCard : null,
            ),
          ],
          'inspect': [
            _ActionButton(
              key: const ValueKey('lab-pcie-inspect'),
              icon: Icons.search_rounded,
              label: _inspected
                  ? MissionContentData.labPcieInspected
                  : MissionContentData.labPcieInspectLabel,
              done: _inspected,
              onPressed: _interactive && !_inspected ? _inspect : null,
            ),
          ],
        }));
        children.add(_ActionButton(
          key: const ValueKey('lab-pcie-contingency'),
          icon: Icons.assignment_turned_in_outlined,
          label: _contingencyReady
              ? MissionContentData.labPcieContingencyDone
              : MissionContentData.labPcieContingencyLabel,
          done: _contingencyReady,
          onPressed:
              widget.enabled && !_contingencyReady ? _recordContingency : null,
        ));
      case _Stage.install:
        children.add(_AdapterTile(
          aligned: _aligned,
          installed: _adapterInstalled,
          selected: _adapterSelected,
          enabled: widget.enabled && !_adapterInstalled,
          label: (_adapter['label'] as String?) ?? '',
          onRotate: () => setState(() => _aligned = !_aligned),
          onSelect: () => setState(() => _adapterSelected = !_adapterSelected),
        ));
      case _Stage.closeOut:
        children.addAll(_inListedOrder({
          'seat': [
            _ActionButton(
              key: const ValueKey('lab-pcie-latch'),
              icon: Icons.vertical_align_bottom_rounded,
              label: _latched
                  ? MissionContentData.labPcieSeated
                  : MissionContentData.labPcieSeatLabel,
              done: _latched,
              onPressed: _interactive && !_latched ? _latch : null,
            ),
          ],
          'fasten': [_toolRow()],
          'configure': [
            _ActionButton(
              key: const ValueKey('lab-pcie-configure'),
              icon: Icons.settings_ethernet_rounded,
              label: _configured
                  ? MissionContentData.labPcieConfigured
                  : MissionContentData.labPcieConfigureLabel,
              done: _configured,
              onPressed: _interactive && !_configured ? _configure : null,
            ),
          ],
          'restore': [
            _ActionButton(
              key: const ValueKey('lab-pcie-panel'),
              icon: Icons.door_back_door_outlined,
              label: _panelOn
                  ? MissionContentData.labPcieClosed
                  : MissionContentData.labPcieCloseLabel,
              done: _panelOn,
              onPressed: _interactive && !_panelOn ? _refitPanel : null,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              key: const ValueKey('lab-pcie-power-back'),
              icon: Icons.power_rounded,
              label: _powerBack
                  ? MissionContentData.labPciePowerConnected
                  : MissionContentData.labPcieRestorePowerLabel,
              done: _powerBack,
              onPressed: _interactive && !_powerBack ? _reconnectPower : null,
            ),
          ],
        }));
    }
    if (_stage != _Stage.install) {
      final valid = _recorded['sequence_valid'] == true;
      final recorded = MissionEquipmentSimulator.strings(_recorded['order']);
      final recordedHere = _submitted && recorded.join(',') == _steps.join(',');
      children.addAll([
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          child: Text(
            MissionContentData.labPcieStepsDone(_steps.length, _items.length),
            style: AppTheme.labelLarge,
          ),
        ),
        if (_toolMessage != null) ...[
          const SizedBox(height: 6),
          Text(_toolMessage!, style: AppTheme.bodySmall),
        ],
        if (recordedHere) ...[
          const SizedBox(height: 8),
          Text(
            _assessment || valid
                ? MissionContentData.labPcieProcedureRecorded
                : MissionContentData.labPcieProcedureOutOfOrder,
            style: AppTheme.bodySmall,
          ),
          // Assessment always offers a fresh attempt, so the button never
          // tells whether the recorded order was safe.
          if (_assessment || !valid) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('lab-pcie-restart'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: widget.enabled ? _restart : null,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text(MissionContentData.labPcieRestartProcedure),
            ),
          ],
        ],
      ]);
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _toolRow() {
    final tools = _stage == _Stage.removal
        ? MissionEquipmentSimulator.maps(_equipment['tools'])
        : const [
            {
              'id': 'esd_driver',
              'label': MissionContentData.labPcieScrewdriverLabel,
            },
          ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(MissionContentData.labPcieToolsTitle, style: AppTheme.labelLarge),
      const SizedBox(height: 4),
      Text(MissionContentData.labPcieToolHint, style: AppTheme.bodySmall),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final tool in tools)
          _ToolChip(
            key: ValueKey('lab-pcie-tool-${tool['id']}'),
            asset: _toolAssets[tool['id']],
            label: tool['label'] as String,
            selected: _tool == tool['id'],
            enabled: widget.enabled,
            onTap: () => setState(() {
              _tool = _tool == tool['id'] ? null : tool['id'] as String;
              _toolMessage = null;
            }),
          ),
      ]),
    ]);
  }
}

class _Interior extends StatelessWidget {
  const _Interior({
    required this.stage,
    required this.cardPresent,
    required this.cardFailed,
    required this.screwIn,
    required this.screwActive,
    required this.slotDroppable,
    required this.panelOn,
    required this.powerConnected,
    required this.strapOn,
    required this.onScrew,
    required this.onSlotTap,
    required this.onAdapterDropped,
  });

  final _Stage stage;
  final bool cardPresent;
  final bool cardFailed;
  final bool screwIn;
  final bool screwActive;
  final bool slotDroppable;
  final bool panelOn;
  final bool powerConnected;
  final bool strapOn;
  final VoidCallback onScrew;
  final VoidCallback? onSlotTap;
  final VoidCallback onAdapterDropped;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(MissionContentData.labPcieTitle, style: AppTheme.labelLarge),
      const SizedBox(height: 2),
      Text(MissionContentData.labPcieInteriorCaption,
          style: AppTheme.bodySmall),
      const SizedBox(height: 8),
      AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(builder: (context, box) {
          final s = box.maxWidth;
          final slot = Rect.fromLTWH(
              _slot.left * s, _slot.top * s, _slot.width * s, _slot.height * s);
          final cardWidth = 0.42 * s;
          final cardHeight = cardWidth * 447 / 558;
          final cardLeft = 0.065 * s;
          final cardTop = slot.center.dy - cardHeight * 0.97;
          final screw =
              Offset(cardLeft + 0.075 * cardWidth, cardTop + 0.1 * cardHeight);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A2335), Color(0xFF0E1522)],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: ExcludeSemantics(
                  child: Image.asset(_motherboardAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              ),
              Positioned.fromRect(
                // At least a 48 dp target around the thin slot.
                rect: Rect.fromCenter(
                    center: slot.center,
                    width: slot.width + 20,
                    height: slot.height + 20 < 48 ? 48 : slot.height + 20),
                child: DragTarget<String>(
                  onWillAcceptWithDetails: (_) => slotDroppable,
                  onAcceptWithDetails: (_) => onAdapterDropped(),
                  builder: (context, candidates, _) => Semantics(
                    button: onSlotTap != null,
                    label: switch (stage) {
                      _Stage.removal => cardPresent
                          ? MissionContentData.labPcieSlotHoldsFailed
                          : MissionContentData.labPcieSlotVacant,
                      _Stage.install => cardPresent
                          ? MissionContentData.labPcieSlotInstalled
                          : MissionContentData.labPcieSlotEmpty,
                      _Stage.closeOut =>
                        MissionContentData.labPcieSlotInstalled,
                    },
                    child: GestureDetector(
                      key: const ValueKey('lab-pcie-slot'),
                      onTap: onSlotTap,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: candidates.isNotEmpty
                                ? AppTheme.successGreen
                                : slotDroppable
                                    ? AppTheme.primaryBlue
                                        .withValues(alpha: 0.9)
                                    : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (cardPresent)
                Positioned(
                  left: cardLeft,
                  top: cardTop,
                  width: cardWidth,
                  height: cardHeight,
                  child: ExcludeSemantics(
                    child: ColorFiltered(
                      colorFilter: cardFailed
                          ? const ColorFilter.mode(
                              Color(0x33FF5A5A), BlendMode.srcATop)
                          : const ColorFilter.mode(
                              Colors.transparent, BlendMode.dst),
                      child: Image.asset(_adapterAsset,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink()),
                    ),
                  ),
                ),
              if (cardPresent && cardFailed)
                Positioned(
                  left: cardLeft + cardWidth * 0.55,
                  top: cardTop + cardHeight * 0.18,
                  child: const _Badge(
                      color: AppTheme.errorRed,
                      text: MissionContentData.labPcieFailedCard),
                ),
              if (cardPresent && stage != _Stage.install)
                Positioned(
                  left: screw.dx - 24,
                  top: screw.dy - 24,
                  width: 48,
                  height: 48,
                  child: Semantics(
                    button: screwActive,
                    label: screwIn
                        ? MissionContentData.labPcieScrewLabel
                        : stage == _Stage.removal
                            ? MissionContentData.labPcieScrewRemoved
                            : MissionContentData.labPcieScrewLabel,
                    child: InkWell(
                      key: const ValueKey('lab-pcie-screw'),
                      customBorder: const CircleBorder(),
                      onTap: screwActive ? onScrew : null,
                      child: Center(
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: screwIn
                                ? const Color(0xFFC9CED6)
                                : Colors.transparent,
                            border: Border.all(
                              color: screwActive
                                  ? AppTheme.primaryBlue
                                  : const Color(0xFF8A93A3),
                              width: screwActive ? 3 : 1.5,
                            ),
                          ),
                          child: screwIn
                              ? const Icon(Icons.add,
                                  size: 12, color: Color(0xFF4B5563))
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              if (panelOn)
                Positioned.fill(
                  child: Container(
                    color: const Color(0xEE2A3242),
                    alignment: Alignment.center,
                    child: Text(MissionContentData.labPcieClosed,
                        style:
                            AppTheme.labelLarge.copyWith(color: Colors.white)),
                  ),
                ),
              Positioned(
                right: 8,
                top: 8,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _Badge(
                        color: powerConnected
                            ? AppTheme.warningYellow
                            : AppTheme.successGreen,
                        text: powerConnected
                            ? MissionContentData.labPciePowerConnected
                            : MissionContentData.labPciePowerIsolated,
                      ),
                      const SizedBox(height: 4),
                      _Badge(
                        color: strapOn
                            ? AppTheme.successGreen
                            : AppTheme.warningYellow,
                        text: strapOn
                            ? MissionContentData.labPcieStrapOn
                            : MissionContentData.labPcieStrapOff,
                      ),
                    ]),
              ),
            ]),
          );
        }),
      ),
    ]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Text(text,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.navy)),
      );
}

class _BenchTile extends StatelessWidget {
  const _BenchTile({
    super.key,
    required this.asset,
    required this.status,
    required this.actionLabel,
    required this.done,
    required this.onPressed,
  });

  final String asset;
  final String status;
  final String actionLabel;
  final bool done;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: done ? AppTheme.successGreen : const Color(0xFFD5DCE8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 64,
          child: ExcludeSemantics(
            child: Image.asset(asset,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        ),
        const SizedBox(height: 4),
        Text(status, style: AppTheme.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        if (!done)
          FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onPressed,
            child: Text(actionLabel, textAlign: TextAlign.center),
          ),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.done,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool done;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        alignment: Alignment.centerLeft,
        foregroundColor: done ? AppTheme.successGreen : null,
        side: done ? const BorderSide(color: AppTheme.successGreen) : null,
      ),
      onPressed: done ? null : onPressed,
      icon: Icon(done ? Icons.check_circle_rounded : icon),
      label: Text(label),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    super.key,
    required this.asset,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String? asset;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56, minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.softBlueAccent : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primaryBlue : const Color(0xFFD5DCE8),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (asset != null)
              ExcludeSemantics(
                child: Image.asset(asset!,
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.handyman_outlined)),
              ),
            const SizedBox(width: 6),
            Flexible(
                child: ExcludeSemantics(
                    child: Text(label, style: AppTheme.bodySmall))),
          ]),
        ),
      ),
    );
  }
}

class _AdapterTile extends StatelessWidget {
  const _AdapterTile({
    required this.aligned,
    required this.installed,
    required this.selected,
    required this.enabled,
    required this.label,
    required this.onRotate,
    required this.onSelect,
  });

  final bool aligned;
  final bool installed;
  final bool selected;
  final bool enabled;
  final String label;
  final VoidCallback onRotate;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final card = Transform(
      alignment: Alignment.center,
      // Reversed: the bracket points into the case instead of the rear.
      transform: Matrix4.diagonal3Values(aligned ? 1 : -1, 1, 1),
      child: Image.asset(_adapterAsset,
          height: 96,
          errorBuilder: (_, __, ___) => const Icon(Icons.memory, size: 64)),
    );
    if (installed) {
      return const _ActionButton(
        icon: Icons.check_circle_rounded,
        label: MissionContentData.labPcieSlotInstalled,
        done: true,
        onPressed: null,
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppTheme.primaryBlue : const Color(0xFFD5DCE8),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          selected: selected,
          label:
              '$label. ${aligned ? MissionContentData.labPcieCardAligned : MissionContentData.labPcieCardReversed}',
          child: Draggable<String>(
            data: 'adapter',
            maxSimultaneousDrags: enabled ? 1 : 0,
            feedback: Material(color: Colors.transparent, child: card),
            childWhenDragging: Opacity(opacity: 0.3, child: card),
            child: InkWell(
              key: const ValueKey('lab-pcie-adapter'),
              onTap: enabled ? onSelect : null,
              child: Center(child: card),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: AppTheme.labelLarge, textAlign: TextAlign.center),
        Text(
          aligned
              ? MissionContentData.labPcieCardAligned
              : MissionContentData.labPcieCardReversed,
          style: AppTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('lab-pcie-rotate'),
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: enabled ? onRotate : null,
          icon: const Icon(Icons.flip_rounded),
          label: const Text(MissionContentData.labPcieRotateLabel),
        ),
      ]),
    );
  }
}
