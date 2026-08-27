import '../format.dart';
import '../job.dart';

/// Reports real progress from inside a converter. [value] is 0.0-1.0.
typedef ProgressSink = void Function(double value, {bool indeterminate});

/// Cooperative cancellation. Converters poll [isCancelled] between units of
/// work and long-running native calls register a [onCancel] hook.
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _hooks = [];

  bool get isCancelled => _cancelled;

  void onCancel(void Function() hook) {
    if (_cancelled) {
      hook();
    } else {
      _hooks.add(hook);
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final h in _hooks) {
      h();
    }
    _hooks.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw ConversionException('Cancelled');
  }
}

class ConvertRequest {
  const ConvertRequest({
    required this.inputPath,
    required this.outputPath,
    required this.from,
    required this.to,
    required this.options,
    required this.onProgress,
    required this.cancel,
    this.extraOutputs,
  });

  final String inputPath;
  final String outputPath;
  final FileFormat from;
  final FileFormat to;
  final ConvertOptions options;
  final ProgressSink onProgress;
  final CancelToken cancel;

  /// Converters that legitimately produce more than one file (a multi-page PDF
  /// rendered to images, for example) append the additional paths here.
  /// [outputPath] always remains the primary result.
  final List<String>? extraOutputs;
}

/// A backend that knows how to turn one family of formats into another.
abstract class FileConverter {
  const FileConverter();

  /// Human name shown in the job detail sheet.
  String get name;

  /// Whether this converter claims the given pair. The first converter in the
  /// engine's list that claims a pair handles it.
  bool supports(FileFormat from, FileFormat to);

  Future<void> convert(ConvertRequest r);
}
