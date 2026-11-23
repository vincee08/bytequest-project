import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/hardware_inspection_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'lens on Android: probe, miss, restore, and finish all seven inspections',
      exerciseHardwareInspection);
}
