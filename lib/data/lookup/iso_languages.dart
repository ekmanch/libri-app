/// Every ISO 639-1 language, for Settings › Languages you read: add a
/// language (DESIGN.md section 4): its two-letter code (the form
/// `settings.json` and the lookups' two-letter codes use), its three-letter
/// ISO 639-2 codes (the bibliographic one first where there are two; Open
/// Library names an edition's languages by them), its English name and its
/// own name.
class IsoLanguage {
  const IsoLanguage(this.code, this.codes3, this.name, this.ownName);

  final String code;
  final List<String> codes3;
  final String name;
  final String ownName;

  /// "Turkish · Türkçe", or the name alone when both are the same.
  String get label => ownName == name ? name : '$name · $ownName';

  /// Whether [query] is in either name, case aside.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        name.toLowerCase().contains(q) ||
        ownName.toLowerCase().contains(q);
  }
}

/// A to Z by English name.
const isoLanguages = <IsoLanguage>[
  IsoLanguage('ab', ['abk'], 'Abkhazian', 'Аҧсуа'),
  IsoLanguage('aa', ['aar'], 'Afar', 'Afaraf'),
  IsoLanguage('af', ['afr'], 'Afrikaans', 'Afrikaans'),
  IsoLanguage('ak', ['aka'], 'Akan', 'Akan'),
  IsoLanguage('sq', ['alb', 'sqi'], 'Albanian', 'Shqip'),
  IsoLanguage('am', ['amh'], 'Amharic', 'አማርኛ'),
  IsoLanguage('ar', ['ara'], 'Arabic', 'العربية'),
  IsoLanguage('an', ['arg'], 'Aragonese', 'Aragonés'),
  IsoLanguage('hy', ['arm', 'hye'], 'Armenian', 'Հայերեն'),
  IsoLanguage('as', ['asm'], 'Assamese', 'অসমীয়া'),
  IsoLanguage('av', ['ava'], 'Avaric', 'Авар мацӀ'),
  IsoLanguage('ae', ['ave'], 'Avestan', 'Avesta'),
  IsoLanguage('ay', ['aym'], 'Aymara', 'Aymar aru'),
  IsoLanguage('az', ['aze'], 'Azerbaijani', 'Azərbaycan dili'),
  IsoLanguage('bm', ['bam'], 'Bambara', 'Bamanankan'),
  IsoLanguage('ba', ['bak'], 'Bashkir', 'Башҡорт теле'),
  IsoLanguage('eu', ['baq', 'eus'], 'Basque', 'Euskara'),
  IsoLanguage('be', ['bel'], 'Belarusian', 'Беларуская'),
  IsoLanguage('bn', ['ben'], 'Bengali', 'বাংলা'),
  IsoLanguage('bh', ['bih'], 'Bihari', 'भोजपुरी'),
  IsoLanguage('bi', ['bis'], 'Bislama', 'Bislama'),
  IsoLanguage('bs', ['bos'], 'Bosnian', 'Bosanski'),
  IsoLanguage('br', ['bre'], 'Breton', 'Brezhoneg'),
  IsoLanguage('bg', ['bul'], 'Bulgarian', 'Български'),
  IsoLanguage('my', ['bur', 'mya'], 'Burmese', 'မြန်မာစာ'),
  IsoLanguage('ca', ['cat'], 'Catalan', 'Català'),
  IsoLanguage('km', ['khm'], 'Central Khmer', 'ខ្មែរ'),
  IsoLanguage('ch', ['cha'], 'Chamorro', 'Chamoru'),
  IsoLanguage('ce', ['che'], 'Chechen', 'Нохчийн мотт'),
  IsoLanguage('ny', ['nya'], 'Chichewa', 'Chichewa'),
  IsoLanguage('zh', ['chi', 'zho'], 'Chinese', '中文'),
  IsoLanguage('cu', ['chu'], 'Church Slavonic', 'Словѣньскъ'),
  IsoLanguage('cv', ['chv'], 'Chuvash', 'Чӑваш чӗлхи'),
  IsoLanguage('kw', ['cor'], 'Cornish', 'Kernewek'),
  IsoLanguage('co', ['cos'], 'Corsican', 'Corsu'),
  IsoLanguage('cr', ['cre'], 'Cree', 'ᓀᐦᐃᔭᐍᐏᐣ'),
  IsoLanguage('hr', ['hrv'], 'Croatian', 'Hrvatski'),
  IsoLanguage('cs', ['cze', 'ces'], 'Czech', 'Čeština'),
  IsoLanguage('da', ['dan'], 'Danish', 'Dansk'),
  IsoLanguage('dv', ['div'], 'Divehi', 'ދިވެހި'),
  IsoLanguage('nl', ['dut', 'nld'], 'Dutch', 'Nederlands'),
  IsoLanguage('dz', ['dzo'], 'Dzongkha', 'རྫོང་ཁ'),
  IsoLanguage('en', ['eng'], 'English', 'English'),
  IsoLanguage('eo', ['epo'], 'Esperanto', 'Esperanto'),
  IsoLanguage('et', ['est'], 'Estonian', 'Eesti'),
  IsoLanguage('ee', ['ewe'], 'Ewe', 'Eʋegbe'),
  IsoLanguage('fo', ['fao'], 'Faroese', 'Føroyskt'),
  IsoLanguage('fj', ['fij'], 'Fijian', 'Vosa Vakaviti'),
  IsoLanguage('fi', ['fin'], 'Finnish', 'Suomi'),
  IsoLanguage('fr', ['fre', 'fra'], 'French', 'Français'),
  IsoLanguage('ff', ['ful'], 'Fulah', 'Fulfulde'),
  IsoLanguage('gd', ['gla'], 'Gaelic', 'Gàidhlig'),
  IsoLanguage('gl', ['glg'], 'Galician', 'Galego'),
  IsoLanguage('lg', ['lug'], 'Ganda', 'Luganda'),
  IsoLanguage('ka', ['geo', 'kat'], 'Georgian', 'ქართული'),
  IsoLanguage('de', ['ger', 'deu'], 'German', 'Deutsch'),
  IsoLanguage('el', ['gre', 'ell'], 'Greek', 'Ελληνικά'),
  IsoLanguage('kl', ['kal'], 'Greenlandic', 'Kalaallisut'),
  IsoLanguage('gn', ['grn'], 'Guarani', "Avañe'ẽ"),
  IsoLanguage('gu', ['guj'], 'Gujarati', 'ગુજરાતી'),
  IsoLanguage('ht', ['hat'], 'Haitian', 'Kreyòl ayisyen'),
  IsoLanguage('ha', ['hau'], 'Hausa', 'Hausa'),
  IsoLanguage('he', ['heb'], 'Hebrew', 'עברית'),
  IsoLanguage('hz', ['her'], 'Herero', 'Otjiherero'),
  IsoLanguage('hi', ['hin'], 'Hindi', 'हिन्दी'),
  IsoLanguage('ho', ['hmo'], 'Hiri Motu', 'Hiri Motu'),
  IsoLanguage('hu', ['hun'], 'Hungarian', 'Magyar'),
  IsoLanguage('is', ['ice', 'isl'], 'Icelandic', 'Íslenska'),
  IsoLanguage('io', ['ido'], 'Ido', 'Ido'),
  IsoLanguage('ig', ['ibo'], 'Igbo', 'Igbo'),
  IsoLanguage('id', ['ind'], 'Indonesian', 'Bahasa Indonesia'),
  IsoLanguage('ia', ['ina'], 'Interlingua', 'Interlingua'),
  IsoLanguage('ie', ['ile'], 'Interlingue', 'Interlingue'),
  IsoLanguage('iu', ['iku'], 'Inuktitut', 'ᐃᓄᒃᑎᑐᑦ'),
  IsoLanguage('ik', ['ipk'], 'Inupiaq', 'Iñupiaq'),
  IsoLanguage('ga', ['gle'], 'Irish', 'Gaeilge'),
  IsoLanguage('it', ['ita'], 'Italian', 'Italiano'),
  IsoLanguage('ja', ['jpn'], 'Japanese', '日本語'),
  IsoLanguage('jv', ['jav'], 'Javanese', 'Basa Jawa'),
  IsoLanguage('kn', ['kan'], 'Kannada', 'ಕನ್ನಡ'),
  IsoLanguage('kr', ['kau'], 'Kanuri', 'Kanuri'),
  IsoLanguage('ks', ['kas'], 'Kashmiri', 'कॉशुर'),
  IsoLanguage('kk', ['kaz'], 'Kazakh', 'Қазақ тілі'),
  IsoLanguage('ki', ['kik'], 'Kikuyu', 'Gĩkũyũ'),
  IsoLanguage('rw', ['kin'], 'Kinyarwanda', 'Ikinyarwanda'),
  IsoLanguage('ky', ['kir'], 'Kirghiz', 'Кыргызча'),
  IsoLanguage('kv', ['kom'], 'Komi', 'Коми кыв'),
  IsoLanguage('kg', ['kon'], 'Kongo', 'Kikongo'),
  IsoLanguage('ko', ['kor'], 'Korean', '한국어'),
  IsoLanguage('kj', ['kua'], 'Kuanyama', 'Kuanyama'),
  IsoLanguage('ku', ['kur'], 'Kurdish', 'Kurdî'),
  IsoLanguage('lo', ['lao'], 'Lao', 'ລາວ'),
  IsoLanguage('la', ['lat'], 'Latin', 'Latina'),
  IsoLanguage('lv', ['lav'], 'Latvian', 'Latviešu'),
  IsoLanguage('li', ['lim'], 'Limburgish', 'Limburgs'),
  IsoLanguage('ln', ['lin'], 'Lingala', 'Lingála'),
  IsoLanguage('lt', ['lit'], 'Lithuanian', 'Lietuvių'),
  IsoLanguage('lu', ['lub'], 'Luba-Katanga', 'Kiluba'),
  IsoLanguage('lb', ['ltz'], 'Luxembourgish', 'Lëtzebuergesch'),
  IsoLanguage('mk', ['mac', 'mkd'], 'Macedonian', 'Македонски'),
  IsoLanguage('mg', ['mlg'], 'Malagasy', 'Malagasy'),
  IsoLanguage('ms', ['may', 'msa'], 'Malay', 'Bahasa Melayu'),
  IsoLanguage('ml', ['mal'], 'Malayalam', 'മലയാളം'),
  IsoLanguage('mt', ['mlt'], 'Maltese', 'Malti'),
  IsoLanguage('gv', ['glv'], 'Manx', 'Gaelg'),
  IsoLanguage('mi', ['mao', 'mri'], 'Maori', 'Te reo Māori'),
  IsoLanguage('mr', ['mar'], 'Marathi', 'मराठी'),
  IsoLanguage('mh', ['mah'], 'Marshallese', 'Kajin M̧ajeļ'),
  IsoLanguage('mn', ['mon'], 'Mongolian', 'Монгол'),
  IsoLanguage('na', ['nau'], 'Nauru', 'Dorerin Naoero'),
  IsoLanguage('nv', ['nav'], 'Navajo', 'Diné bizaad'),
  IsoLanguage('ng', ['ndo'], 'Ndonga', 'Owambo'),
  IsoLanguage('ne', ['nep'], 'Nepali', 'नेपाली'),
  IsoLanguage('nd', ['nde'], 'North Ndebele', 'isiNdebele'),
  IsoLanguage('se', ['sme'], 'Northern Sami', 'Davvisámegiella'),
  IsoLanguage('no', ['nor'], 'Norwegian', 'Norsk'),
  IsoLanguage('nb', ['nob'], 'Norwegian Bokmål', 'Norsk bokmål'),
  IsoLanguage('nn', ['nno'], 'Norwegian Nynorsk', 'Norsk nynorsk'),
  IsoLanguage('oc', ['oci'], 'Occitan', 'Occitan'),
  IsoLanguage('oj', ['oji'], 'Ojibwa', 'ᐊᓂᔑᓈᐯᒧᐎᓐ'),
  IsoLanguage('or', ['ori'], 'Oriya', 'ଓଡ଼ିଆ'),
  IsoLanguage('om', ['orm'], 'Oromo', 'Afaan Oromoo'),
  IsoLanguage('os', ['oss'], 'Ossetian', 'Ирон æвзаг'),
  IsoLanguage('pi', ['pli'], 'Pali', 'पालि'),
  IsoLanguage('ps', ['pus'], 'Pashto', 'پښتو'),
  IsoLanguage('fa', ['per', 'fas'], 'Persian', 'فارسی'),
  IsoLanguage('pl', ['pol'], 'Polish', 'Polski'),
  IsoLanguage('pt', ['por'], 'Portuguese', 'Português'),
  IsoLanguage('pa', ['pan'], 'Punjabi', 'ਪੰਜਾਬੀ'),
  IsoLanguage('qu', ['que'], 'Quechua', 'Runa simi'),
  IsoLanguage('ro', ['rum', 'ron'], 'Romanian', 'Română'),
  IsoLanguage('rm', ['roh'], 'Romansh', 'Rumantsch'),
  IsoLanguage('rn', ['run'], 'Rundi', 'Ikirundi'),
  IsoLanguage('ru', ['rus'], 'Russian', 'Русский'),
  IsoLanguage('sm', ['smo'], 'Samoan', "Gagana fa'a Samoa"),
  IsoLanguage('sg', ['sag'], 'Sango', 'Yângâ tî sängö'),
  IsoLanguage('sa', ['san'], 'Sanskrit', 'संस्कृतम्'),
  IsoLanguage('sc', ['srd'], 'Sardinian', 'Sardu'),
  IsoLanguage('sr', ['srp'], 'Serbian', 'Српски'),
  IsoLanguage('sn', ['sna'], 'Shona', 'chiShona'),
  IsoLanguage('ii', ['iii'], 'Sichuan Yi', 'ꆈꌠ꒿'),
  IsoLanguage('sd', ['snd'], 'Sindhi', 'سنڌي'),
  IsoLanguage('si', ['sin'], 'Sinhala', 'සිංහල'),
  IsoLanguage('sk', ['slo', 'slk'], 'Slovak', 'Slovenčina'),
  IsoLanguage('sl', ['slv'], 'Slovenian', 'Slovenščina'),
  IsoLanguage('so', ['som'], 'Somali', 'Soomaali'),
  IsoLanguage('nr', ['nbl'], 'South Ndebele', 'isiNdebele'),
  IsoLanguage('st', ['sot'], 'Southern Sotho', 'Sesotho'),
  IsoLanguage('es', ['spa'], 'Spanish', 'Español'),
  IsoLanguage('su', ['sun'], 'Sundanese', 'Basa Sunda'),
  IsoLanguage('sw', ['swa'], 'Swahili', 'Kiswahili'),
  IsoLanguage('ss', ['ssw'], 'Swati', 'SiSwati'),
  IsoLanguage('sv', ['swe'], 'Swedish', 'Svenska'),
  IsoLanguage('tl', ['tgl'], 'Tagalog', 'Tagalog'),
  IsoLanguage('ty', ['tah'], 'Tahitian', 'Reo Tahiti'),
  IsoLanguage('tg', ['tgk'], 'Tajik', 'Тоҷикӣ'),
  IsoLanguage('ta', ['tam'], 'Tamil', 'தமிழ்'),
  IsoLanguage('tt', ['tat'], 'Tatar', 'Татарча'),
  IsoLanguage('te', ['tel'], 'Telugu', 'తెలుగు'),
  IsoLanguage('th', ['tha'], 'Thai', 'ไทย'),
  IsoLanguage('bo', ['tib', 'bod'], 'Tibetan', 'བོད་ཡིག'),
  IsoLanguage('ti', ['tir'], 'Tigrinya', 'ትግርኛ'),
  IsoLanguage('to', ['ton'], 'Tonga', 'Faka Tonga'),
  IsoLanguage('ts', ['tso'], 'Tsonga', 'Xitsonga'),
  IsoLanguage('tn', ['tsn'], 'Tswana', 'Setswana'),
  IsoLanguage('tr', ['tur'], 'Turkish', 'Türkçe'),
  IsoLanguage('tk', ['tuk'], 'Turkmen', 'Türkmençe'),
  IsoLanguage('tw', ['twi'], 'Twi', 'Twi'),
  IsoLanguage('ug', ['uig'], 'Uighur', 'ئۇيغۇرچە'),
  IsoLanguage('uk', ['ukr'], 'Ukrainian', 'Українська'),
  IsoLanguage('ur', ['urd'], 'Urdu', 'اردو'),
  IsoLanguage('uz', ['uzb'], 'Uzbek', "Oʻzbek"),
  IsoLanguage('ve', ['ven'], 'Venda', 'Tshivenḓa'),
  IsoLanguage('vi', ['vie'], 'Vietnamese', 'Tiếng Việt'),
  IsoLanguage('vo', ['vol'], 'Volapük', 'Volapük'),
  IsoLanguage('wa', ['wln'], 'Walloon', 'Walon'),
  IsoLanguage('cy', ['wel', 'cym'], 'Welsh', 'Cymraeg'),
  IsoLanguage('fy', ['fry'], 'Western Frisian', 'Frysk'),
  IsoLanguage('wo', ['wol'], 'Wolof', 'Wolof'),
  IsoLanguage('xh', ['xho'], 'Xhosa', 'isiXhosa'),
  IsoLanguage('yi', ['yid'], 'Yiddish', 'ייִדיש'),
  IsoLanguage('yo', ['yor'], 'Yoruba', 'Yorùbá'),
  IsoLanguage('za', ['zha'], 'Zhuang', 'Saɯ cueŋƅ'),
  IsoLanguage('zu', ['zul'], 'Zulu', 'isiZulu'),
];

final Map<String, IsoLanguage> _byCode = {
  for (final l in isoLanguages) l.code: l,
};

final Map<String, IsoLanguage> _byCode3 = {
  for (final l in isoLanguages)
    for (final c in l.codes3) c: l,
};

/// The language with the two-letter [code] ("sv"), or by a three-letter
/// code or a locale ("swe", "sv-SE", "sv_SE"); null for a code not listed.
IsoLanguage? isoLanguage(String? code) {
  if (code == null) return null;
  final base = code.trim().toLowerCase().split(RegExp(r'[-_]')).first;
  return _byCode[base] ?? _byCode3[base];
}

/// The two-letter code a lookup's language code names ("eng" is "en",
/// "ja-JP" is "ja"), or null when it is not an ISO 639-1 language.
String? isoLanguageCode(String? code) => isoLanguage(code)?.code;

/// "English, Swedish" for a list of codes, by English name, A to Z; a code
/// not listed shows as itself.
String isoLanguageNames(Iterable<String> codes) {
  final names = [for (final c in codes) isoLanguage(c)?.name ?? c]..sort();
  return names.join(', ');
}

/// The languages the owner reads before they chose any (Settings › Books ›
/// Languages you read; DESIGN.md section 8): every language in the phone's
/// system language list ([systemLanguages], as locale codes, in the phone's
/// order), plus English; each once, A to Z by code.
List<String> defaultReadingLanguages(Iterable<String> systemLanguages) {
  final codes = <String>{
    for (final l in systemLanguages) ?isoLanguageCode(l),
    'en',
  };
  return codes.toList()..sort();
}
