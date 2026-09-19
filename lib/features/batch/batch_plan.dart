import '../../engine/engine.dart';
import '../../engine/format.dart';

/// What a queued file becomes in a batch, or null when this build cannot do it.
///
/// Two modes share one queue. A conversion sends every file to the same target;
/// an optimize re-encodes each file into its own format, so its target comes
/// from the file rather than from the page — which is the whole point of
/// optimizing a mixed queue, and also why there is nothing to pick.
///
/// Both answers are asked of the engine rather than assumed, so the queue's own
/// arithmetic — how many files are ready, how many will be skipped, what the
/// button says — is the same answer the run loop gets. A second guess here
/// could only drift from it, and the drift would be visible as a count that
/// disagrees with how many files actually came out.
FileFormat? batchTargetFor({
  required FileFormat? source,
  required FileFormat? shared,
  required bool optimize,
}) {
  // A file this build cannot read is not a conversion that failed, it is one
  // that was never going to start. It is skipped rather than queued and failed.
  if (source == null) return null;

  if (optimize) {
    // Read *and* write, and a converter that genuinely re-encodes: the same
    // gate the single-file Optimize screen uses. A lossless-audio queue, or one
    // full of formats with no encoder in this build, has nothing to optimize
    // and needs to say so before the run rather than after 200 failures.
    return ConversionEngine.instance.canOptimize(source) ? source : null;
  }

  if (shared == null) return null;
  return ConversionEngine.instance.canConvert(source, shared) ? shared : null;
}
