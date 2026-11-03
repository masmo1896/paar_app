// Einstellungen, die nicht zum normalen Code gehören.

/// GIPHY-API-Schlüssel für die GIF-Suche (kostenlos auf developers.giphy.com).
/// Kommt NICHT aus dem Code, sondern aus der lokalen Datei dart_defines.json
/// (siehe dart_defines.example.json; die echte Datei ist nicht in Git).
/// Leer = Suche ausgeschaltet; GIFs aus der Galerie funktionieren trotzdem.
const giphyApiKey = String.fromEnvironment('GIPHY_API_KEY');
