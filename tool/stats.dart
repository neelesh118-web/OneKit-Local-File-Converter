// Prints the registry's shape. Handy when the catalogue changes.
// ignore_for_file: avoid_print
import 'package:onekit_converter/engine/format.dart';
import 'package:onekit_converter/engine/registry.dart';

void main() {
  print('formats: ${FormatRegistry.all.length}');
  print('pairs:   ${FormatRegistry.pairCount}');
  for (final f in Family.values) {
    final n = FormatRegistry.family(f).length;
    if (n > 0) print('  ${f.label}: $n');
  }
}
