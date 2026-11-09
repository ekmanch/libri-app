/// Where Libri's source lives, named in the User-Agent.
const _source = 'https://github.com/ekmanch/library-app';

/// The User-Agent for the build [version]: who is asking, with a link
/// back, as Wikimedia's User-Agent policy asks. Wikidata throttles a bare
/// "Libri" (the desktop app got 429 with a two-minute Retry-After for it
/// on 2026-11-09, and so never learned who had died).
String userAgentFor(String version) => 'Libri/$version ($_source)';

/// What the lookups and the image downloads send as their User-Agent.
/// `main` sets it from the build's version before anything is asked;
/// until then (the tests) it names no version.
String lookupUserAgent = 'Libri ($_source)';
