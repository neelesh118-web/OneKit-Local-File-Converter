// Prints the registry's shape. Handy when the catalogue changes.
// ignore_for_file: avoid_print
import 'package:onekit_converter/engine/format.dart';
import 'package:onekit_converter/engine/registry.dart';

void main() {
  print('formats: ${FormatRegistry.all.length}');
  print('pairs:   ${FormatRegistry.pairCount}');

  print('\nformats by family:');
  for (final f in Family.values) {
    final n = FormatRegistry.family(f).length;
    if (n > 0) print('  ${f.label}: $n');
  }

  print('\nsame-family pairs: ${FormatRegistry.sameFamilyPairCount}');
  final cross = FormatRegistry.crossFamilyPairCounts;
  if (cross.isNotEmpty) {
    print('cross-family pairs: ${FormatRegistry.crossFamilyPairTotal}');
    for (final e in cross.entries.toList()..sort((a, b) => b.value - a.value)) {
      print('  -> ${e.key.label}: ${e.value}');
    }
  }

  print('\nreadable formats: ${FormatRegistry.readable.length}');
  print('writable formats: ${FormatRegistry.writable.length}');
}
