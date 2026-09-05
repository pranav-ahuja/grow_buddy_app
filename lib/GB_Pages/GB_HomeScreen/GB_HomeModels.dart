/// One card in the events carousel.
///
/// [imagePath] is an asset path for now. When events come from the backend this
/// becomes a URL and the card swaps `Image.asset` for `Image.network`; nothing
/// else about the card changes.
///
/// Shared with the class screen, which shows the same card for one class's
/// events.
class GB_Event {
  final String title;

  /// The line under the title — on the design, "Classes: Nursery & KG".
  final String subtitle;
  final String imagePath;

  const GB_Event({
    required this.title,
    required this.subtitle,
    required this.imagePath,
  });
}
