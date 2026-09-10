/// Island JSON shaped exactly as `GET /v1/islands` returns it (§Phase 7).
///
/// `displayName` is the **server's** rule and is spelled out here rather than
/// computed, so a fixture cannot accidentally agree with a client-side copy of
/// a rule the client must not have: an ambiguous name carries its atoll code,
/// an unambiguous one stands alone.
Map<String, dynamic> islandJson({
  required String id,
  required String name,
  required String atollName,
  required String atollAbbr,
  bool nameAmbiguous = false,
}) => {
  'id': id,
  'name': name,
  'displayName': nameAmbiguous ? '$atollAbbr. $name' : name,
  'atollName': atollName,
  'atollAbbr': atollAbbr,
  'nameAmbiguous': nameAmbiguous,
};

/// A slice of the real register, chosen for what it exercises: the three
/// Meedhoos, the apostrophe pair that only a normalised grouping separates,
/// a name with an internal apostrophe, and two unambiguous islands.
List<Map<String, dynamic>> sampleIslands() => [
  islandJson(id: 'i-male', name: "Male'", atollName: 'Kaafu', atollAbbr: 'K'),
  islandJson(
    id: 'i-kulhudhuffushi',
    name: 'Kulhudhuffushi',
    atollName: 'Haa Dhaalu',
    atollAbbr: 'HDh',
  ),
  islandJson(
    id: 'i-angolhitheemu',
    name: "An'golhitheemu",
    atollName: 'Raa',
    atollAbbr: 'R',
  ),
  islandJson(
    id: 'i-meedhoo-dh',
    name: 'Meedhoo',
    atollName: 'Dhaalu',
    atollAbbr: 'Dh',
    nameAmbiguous: true,
  ),
  islandJson(
    id: 'i-meedhoo-r',
    name: 'Meedhoo',
    atollName: 'Raa',
    atollAbbr: 'R',
    nameAmbiguous: true,
  ),
  islandJson(
    id: 'i-meedhoo-s',
    name: 'Meedhoo',
    atollName: 'Seenu',
    atollAbbr: 'S',
    nameAmbiguous: true,
  ),
  islandJson(
    id: 'i-vilingili-k',
    name: 'Vilingili',
    atollName: 'Kaafu',
    atollAbbr: 'K',
    nameAmbiguous: true,
  ),
  islandJson(
    id: 'i-vilingili-ga',
    name: "Vilin'gili",
    atollName: 'Gaafu Alifu',
    atollAbbr: 'GA',
    nameAmbiguous: true,
  ),
];
