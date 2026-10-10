/// Formatea una duración como `m:ss` o `h:mm:ss`.
String formatDuration(Duration duration) {
  final d = duration.isNegative ? Duration.zero : duration;
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// `1 canción` / `n canciones`.
String songCountLabel(int count) =>
    count == 1 ? '1 canción' : '$count canciones';
