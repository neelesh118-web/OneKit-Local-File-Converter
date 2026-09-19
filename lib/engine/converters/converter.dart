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
    this.optimize = false,
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

  /// True when this is an Optimize job: [from] and [to] are the same format and
  /// the file is being re-encoded smaller rather than converted. Any stream-copy
  /// shortcut has to be skipped — copying a file into its own container is a
  /// no-op, which is the opposite of what the user asked for.
  final bool optimize;
}

/// A backend that knows how to turn one family of formats into another.
abstract class FileConverter {
  const FileConverter();

  /// Human name shown in the job detail sheet.
  String get name;

  /// Whether this converter claims the given pair. The first converter in the
  /// engine's list that claims a pair handles it.
  bool supports(FileFormat from, FileFormat to);

  /// Whether this converter can re-encode [format] into itself at a smaller
  /// size — the Optimize path.
  ///
  /// This is deliberately not part of [supports], and self-pairs are never part
  /// of the advertised conversion matrix: "JPG to JPG" is not a conversion, and
  /// a catalogue that lists it would be claiming a route no converter offers.
  /// A converter that answers true here must genuinely re-encode the file, at
  /// lower quality or smaller dimensions, and report a real result either way.
  /// The default is no, so a converter has to opt in explicitly.
  bool supportsOptimize(FileFormat format) => false;

  Future<void> convert(ConvertRequest r);
}
