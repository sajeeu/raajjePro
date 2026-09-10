/// One inhabited island, exactly as `GET /v1/islands` gave it (§Phase 7,
/// §0.0 item 12).
///
/// **[id] is the identifier; [name] is not.** Sixteen normalised island names
/// occur in more than one atoll and `Meedhoo` exists in three, so a service
/// area, a booking location or a filter that stored or matched on the name
/// would silently mis-route. Nothing in this app compares islands by name.
///
/// **[displayName] is the server's, not this class's.** The qualifying rule —
/// `Dh. Meedhoo` where the name is shared, `Kulhudhuffushi` where it is not —
/// is decided once on the backend so that every surface prints the same
/// string. Rebuilding it here from [nameAmbiguous] would be a second copy of a
/// rule that already has one.
class Island {
  const Island({
    required this.id,
    required this.name,
    required this.displayName,
    required this.atollName,
    required this.atollAbbr,
    required this.nameAmbiguous,
  });

  factory Island.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    return Island(
      id: json['id'] as String,
      name: name,
      // The server always sends it; the fallback is the bare name rather than
      // an empty string, so a row can never render blank.
      displayName: json['displayName'] as String? ?? name,
      atollName: json['atollName'] as String? ?? '',
      atollAbbr: json['atollAbbr'] as String? ?? '',
      nameAmbiguous: json['nameAmbiguous'] as bool? ?? false,
    );
  }

  final String id;

  /// The register spelling, apostrophes intact — `An'golhitheemu`, `Male'`.
  final String name;

  /// What a screen prints. Qualified with the atoll code where the name is
  /// shared, bare where it is not.
  final String displayName;

  /// The administrative atoll — `Haa Dhaalu`. It travels with the island
  /// everywhere: a screen that resolves the ambiguity at selection time and
  /// then shows the bare name afterwards has not fixed anything.
  final String atollName;

  /// The standard atoll code — `HDh`.
  final String atollAbbr;

  final bool nameAmbiguous;

  @override
  bool operator ==(Object other) => other is Island && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
