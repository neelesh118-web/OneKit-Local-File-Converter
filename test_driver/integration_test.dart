// Driver for `flutter drive`, which is how the matrix suite is run in profile
// mode. That matters: profile and release are AOT-compiled, and at least one
// bug (an isolate closure capturing non-sendable state) reproduced only there.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
