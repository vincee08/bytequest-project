import 'package:bytequest/screens/simulation/components/physical/physical_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _socket = PhysicalMount('socket', Rect.fromLTWH(200, 50, 20, 30),
    capture: Rect.fromLTWH(196, 46, 28, 38));

void main() {
  test('snap uses the occupied location, not a nearby correct answer', () {
    const neighbor = PhysicalMount('header', Rect.fromLTWH(220, 50, 20, 30),
        capture: Rect.fromLTWH(216, 46, 28, 38));
    for (final mounts in [[_socket, neighbor], [neighbor, _socket]]) {
      expect(PhysicalMount.at(const Offset(221, 60), mounts), same(neighbor));
      expect(PhysicalMount.at(const Offset(199, 65), mounts), same(_socket));
      expect(PhysicalMount.at(const Offset(185, 65), mounts), isNull);
    }
    final top = PhysicalMount('top', _socket.bounds, layer: 1);
    expect(PhysicalMount.at(_socket.snapPoint, [_socket, top]), same(top));
  });

  const sourceKey = ValueKey('loose-source');
  const boardKey = ValueKey('test-board');
  const ghostKey = ValueKey('lifted-sprite');
  const previewKey = ValueKey('test-preview');
  final releases = <(String, Offset, String?)>[];

  Widget app({bool enabled = true}) => MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(
          width: 460, height: 260,
          child: Row(children: [
            PhysicalDraggable<String>(
              data: 'held',
              feedbackAnchor: const Offset(.3, .85),
              feedback: const ColoredBox(key: ghostKey, color: Colors.blue,
                  child: SizedBox(width: 90, height: 60)),
              child: const SizedBox(key: sourceKey, width: 64, height: 64,
                  child: ColoredBox(color: Colors.grey)),
            ),
            const SizedBox(width: 25),
            Transform.scale(scale: .85, alignment: Alignment.centerLeft,
              child: SizedBox(width: 350, height: 200,
                child: PhysicalDropSurface<String>(
                  worldSize: const Size(350, 200), enabled: enabled,
                  mounts: (_) => [_socket],
                  onRelease: (id, p, mount) => releases.add((id, p, mount?.id)),
                  preview: (_, __, point, ___) => Positioned(
                    left: point.dx - 2, top: point.dy - 2,
                    child: const SizedBox(key: previewKey, width: 4, height: 4)),
                  child: const ColoredBox(key: boardKey, color: Colors.black),
                ),
              )),
          ]),
        ))),
      );

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('sprite and cable tip follow $kind; release uses world coordinates', (tester) async {
      releases.clear();
      await tester.pumpWidget(app());
      final board = tester.renderObject<RenderBox>(find.byKey(boardKey));
      final drag = await tester.startGesture(tester.getCenter(find.byKey(sourceKey)), kind: kind);
      for (var i = 0; i < 65; i++) {
        final finger = board.localToGlobal(Offset(40 + 2.5 * i, 65));
        await drag.moveTo(finger);
        await tester.pump(const Duration(milliseconds: 16));
        expect(releases, isEmpty);
        final sprite = tester.getRect(find.byKey(ghostKey));
        expect((sprite.topLeft + const Offset(27, 51) - finger).distance, lessThan(.01));
        expect((tester.getCenter(find.byKey(previewKey)) - finger).distance, lessThan(.01));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(releases.single.$1, 'held');
      expect((releases.single.$2 - const Offset(200, 65)).distance, lessThan(.01));
      expect(releases.single.$3, 'socket');
      expect(find.byKey(previewKey), findsNothing);
    });
  }

  testWidgets('miss inside parks; outside, cancelled and disabled drags never commit', (tester) async {
    releases.clear();
    await tester.pumpWidget(app());
    final rect = tester.getRect(find.byKey(boardKey));
    Future<TestGesture> ontoBoard() async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(sourceKey)));
      await g.moveTo(rect.topLeft + const Offset(30, 30));
      await tester.pump();
      return g;
    }
    await (await ontoBoard()).up();
    await tester.pump();
    expect(releases.single.$3, isNull);
    await (await ontoBoard()).cancel();
    await tester.pump();
    final escaped = await ontoBoard();
    await escaped.moveTo(rect.bottomRight + const Offset(10, 10));
    await escaped.up();
    await tester.pump();
    final interrupted = await ontoBoard();
    await tester.pumpWidget(app(enabled: false));
    await interrupted.up();
    await tester.pump();
    expect(releases, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
