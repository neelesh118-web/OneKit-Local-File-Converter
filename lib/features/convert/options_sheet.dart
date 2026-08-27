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
  });

  final FileFormat source;
  final FileFormat target;
  final ConvertOptions options;

  @override
  State<OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<OptionsSheet> {
  late ConvertOptions _o = widget.options;
  late final TextEditingController _width =
      TextEditingController(text: widget.options.width?.toString() ?? '');
  late final TextEditingController _height =
      TextEditingController(text: widget.options.height?.toString() ?? '');
  late final TextEditingController _pages =
      TextEditingController(text: widget.options.pdfPageRange ?? '');

  bool get _showQuality =>
      widget.target.lossy && (widget.target.family == Family.image);
  bool get _showResize =>
      widget.target.family == Family.image || widget.target.family == Family.video;
  bool get _showAudio => widget.target.family == Family.audio;
  bool get _showVideo => widget.target.family == Family.video;
  bool get _showPdfSource => widget.source.ext == 'pdf';
  bool get _showFps =>
      widget.target.family == Family.video ||
      (widget.source.family == Family.video &&
          {'gif', 'apng', 'webp'}.contains(widget.target.ext));

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.pop(
      context,
      _o.copyWith(
        width: int.tryParse(_width.text.trim()),
        height: int.tryParse(_height.text.trim()),
        pdfPageRange: _pages.text.trim().isEmpty ? null : _pages.text.trim(),
      ),
    );
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
                Text('${widget.target.upper} options',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Leave anything blank to keep the original.',
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
