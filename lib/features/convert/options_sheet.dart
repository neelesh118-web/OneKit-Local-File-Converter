import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../engine/format.dart';
import '../../engine/job.dart';

/// Conversion settings, scoped to whatever the chosen target actually supports.
///
/// A PNG target never shows an audio bitrate; an MP3 target never shows a
/// resize field. Anything left untouched keeps the source's own value.
class OptionsSheet extends StatefulWidget {
  const OptionsSheet({
    super.key,
    required this.source,
    required this.target,
    required this.options,
    this.onSavePreset,
  }) : formats = const [];

  /// The same sheet for a queue that spans formats — a batch Optimize, where
  /// each file is re-encoded into its own format. There is no single target to
  /// scope the sheet to, so a control appears when at least one file in the
  /// queue understands it, and the settings apply to all of them.
  const OptionsSheet.batch({
    super.key,
    required this.formats,
    required this.options,
    this.onSavePreset,
  })  : source = null,
        target = null;

  final FileFormat? source;
  final FileFormat? target;
  final ConvertOptions options;

  /// Every format the sheet speaks for, when it spans more than one.
  final List<FileFormat> formats;

  /// Called when the user asks to keep these settings for later.
  ///
  /// The sheet does not know what the job is — a target format, or the file's
  /// own format when optimizing — so naming and storing it belongs to the
  /// screen that opened the sheet. Returns the name that was saved, or null
  /// when the user backed out, which the sheet shows as a line of confirmation
  /// rather than a snackbar it could not see behind itself.
  final Future<String?> Function(ConvertOptions options)? onSavePreset;

  @override
  State<OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<OptionsSheet> {
  late ConvertOptions _o = widget.options;

  /// Set once the settings have been kept as a preset, so the sheet can confirm
  /// it without closing.
  String? _savedName;
  late final TextEditingController _width =
      TextEditingController(text: widget.options.width?.toString() ?? '');
  late final TextEditingController _height =
      TextEditingController(text: widget.options.height?.toString() ?? '');
  late final TextEditingController _pages =
      TextEditingController(text: widget.options.pdfPageRange ?? '');

  /// What the sheet speaks for. One target for a conversion; every file in the
  /// queue for a batch. Empty lists rather than null assertions, so a sheet
  /// with nothing to describe still renders its one universal control instead
  /// of throwing.
  Iterable<FileFormat> get _targets =>
      widget.formats.isNotEmpty ? widget.formats : [if (widget.target != null) widget.target!];
  Iterable<FileFormat> get _sources =>
      widget.formats.isNotEmpty ? widget.formats : [if (widget.source != null) widget.source!];

  bool get _showQuality =>
      _targets.any((f) => f.lossy && f.family == Family.image);
  bool get _showResize =>
      _targets.any((f) => f.family == Family.image || f.family == Family.video);
  bool get _showAudio => _targets.any((f) => f.family == Family.audio);
  bool get _showVideo => _targets.any((f) => f.family == Family.video);
  bool get _showPdfSource => _sources.any((f) => f.ext == 'pdf');
  bool get _showFps =>
      _targets.any((f) => f.family == Family.video) ||
      // A video source rendered into an animated image is the one case where
      // the target is not a video but the frame rate still applies. It needs a
      // pair, which a mixed queue does not have.
      (widget.formats.isEmpty &&
          widget.source!.family == Family.video &&
          {'gif', 'apng', 'webp'}.contains(widget.target!.ext));

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _pages.dispose();
    super.dispose();
  }

  /// The settings as they stand, including cleared fields.
  ///
  /// Built field by field rather than with `copyWith`, which cannot clear one:
  /// a resize box the user emptied has to mean no resize, not the last number
  /// that was typed in it — and a recipe that is saved has to be the recipe that
  /// runs.
  ConvertOptions get _current => ConvertOptions(
        quality: _o.quality,
        width: int.tryParse(_width.text.trim()),
        height: int.tryParse(_height.text.trim()),
        audioBitrateKbps: _o.audioBitrateKbps,
        sampleRate: _o.sampleRate,
        videoCrf: _o.videoCrf,
        fps: _o.fps,
        stripMetadata: _o.stripMetadata,
        pdfPageRange: _pages.text.trim().isEmpty ? null : _pages.text.trim(),
        pdfDpi: _o.pdfDpi,
        maxEdge: _o.maxEdge,
      );

  void _apply() => Navigator.pop(context, _current);

  Future<void> _savePreset() async {
    final save = widget.onSavePreset;
    if (save == null) return;
    final name = await save(_current);
    if (name != null && mounted) setState(() => _savedName = name);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.formats.isEmpty
                      ? '${widget.target!.upper} options'
                      : 'Optimize options',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.formats.isEmpty
                      ? 'Leave anything blank to keep the original.'
                      : 'One setting for the whole queue — each file is re-encoded '
                          'into its own format. Leave anything blank to keep the '
                          'original.',
                  style: TextStyle(fontSize: 13, color: t.textFaint),
                ),
                const SizedBox(height: 18),

                if (_showQuality) ...[
                  _label('Quality', '${_o.quality}'),
                  Slider(
                    value: _o.quality.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    onChanged: (v) => setState(() => _o = _o.copyWith(quality: v.round())),
                  ),
                  const SizedBox(height: 6),
                ],

                if (_showResize) ...[
                  _label('Resize', 'pixels'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _numField(_width, 'Width')),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.close_rounded, size: 16, color: t.textFaint),
                      ),
                      Expanded(child: _numField(_height, 'Height')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Set one side only to keep the aspect ratio.',
                    style: TextStyle(fontSize: 12, color: t.textFaint),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_showAudio) ...[
                  _label('Bitrate', _o.audioBitrateKbps == null ? 'Auto' : '${_o.audioBitrateKbps} kbps'),
                  const SizedBox(height: 8),
                  _chips<int?>(
                    values: const [null, 96, 128, 192, 256, 320],
                    current: _o.audioBitrateKbps,
                    labelOf: (v) => v == null ? 'Auto' : '$v',
                    onPick: (v) => setState(() => _o = ConvertOptions(
                          quality: _o.quality,
                          audioBitrateKbps: v,
                          sampleRate: _o.sampleRate,
                          stripMetadata: _o.stripMetadata,
                        )),
                  ),
                  const SizedBox(height: 16),
                  _label('Sample rate', _o.sampleRate == null ? 'Auto' : '${_o.sampleRate} Hz'),
                  const SizedBox(height: 8),
                  _chips<int?>(
                    values: const [null, 22050, 44100, 48000],
                    current: _o.sampleRate,
                    labelOf: (v) => v == null ? 'Auto' : '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k',
                    onPick: (v) => setState(() => _o = ConvertOptions(
                          quality: _o.quality,
                          audioBitrateKbps: _o.audioBitrateKbps,
                          sampleRate: v,
                          stripMetadata: _o.stripMetadata,
                        )),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_showVideo) ...[
                  _label('Video quality', _o.videoCrf == null ? 'Auto' : 'CRF ${_o.videoCrf}'),
                  const SizedBox(height: 8),
                  _chips<int?>(
                    values: const [null, 18, 23, 28, 32],
                    current: _o.videoCrf,
                    labelOf: (v) => switch (v) {
                      null => 'Auto',
                      18 => 'Best',
                      23 => 'High',
                      28 => 'Small',
                      _ => 'Tiny',
                    },
                    onPick: (v) => setState(() => _o = _o.copyWith(videoCrf: v)),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_showFps) ...[
                  _label('Frame rate', _o.fps == null ? 'Auto' : '${_o.fps} fps'),
                  const SizedBox(height: 8),
                  _chips<int?>(
                    values: const [null, 10, 15, 24, 30, 60],
                    current: _o.fps,
                    labelOf: (v) => v == null ? 'Auto' : '$v',
                    onPick: (v) => setState(() => _o = _o.copyWith(fps: v)),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_showPdfSource) ...[
                  _label('Pages', 'e.g. 1-3, 7'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pages,
                    decoration: const InputDecoration(hintText: 'All pages'),
                  ),
                  const SizedBox(height: 16),
                  _label('Render density', '${_o.pdfDpi} dpi'),
                  const SizedBox(height: 8),
                  _chips<int>(
                    values: const [72, 150, 300, 600],
                    current: _o.pdfDpi,
                    labelOf: (v) => '$v',
                    onPick: (v) => setState(() => _o = _o.copyWith(pdfDpi: v)),
                  ),
                  const SizedBox(height: 16),
                ],

                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _o.stripMetadata,
                  onChanged: (v) => setState(() => _o = _o.copyWith(stripMetadata: v)),
                  title: const Text('Remove metadata'),
                  subtitle: Text(
                    'Strips EXIF, location and tags from the output.',
                    style: TextStyle(fontSize: 12.5, color: t.textFaint),
                  ),
                ),

                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: _apply, child: const Text('Apply')),
                ),
                if (widget.onSavePreset != null) ...[
                  const SizedBox(height: 4),
                  if (_savedName != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.bookmark_added_outlined, size: 17, color: t.textFaint),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Saved as "$_savedName". It is on Home and above the '
                              'target grid, and runs in one tap from there.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: t.textFaint,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _savePreset,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Save as a preset'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String title, String value) {
    final t = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        Text(value, style: TextStyle(fontSize: 13, color: t.textFaint, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _numField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
      decoration: InputDecoration(hintText: hint),
    );
  }

  Widget _chips<T>({
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required ValueChanged<T> onPick,
  }) {
    final t = context.tokens;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          InkWell(
            onTap: () => onPick(v),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: v == current ? t.accent : Colors.transparent,
                border: Border.all(color: v == current ? t.accent : t.border),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Text(
                labelOf(v),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: v == current ? t.onAccent : t.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
