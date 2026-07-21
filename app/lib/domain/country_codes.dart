/// Country dial codes + E.164 phone helpers. Pure Dart → unit-testable.
/// CIS/Central-Asia-first list (the product's primary market), plus common others.
library;

class Country {
  final String iso; // 'KZ'
  final String name; // 'Kazakhstan'
  final String dial; // '+7'
  final String flag; // '🇰🇿'
  const Country(this.iso, this.name, this.dial, this.flag);
}

const countries = <Country>[
  Country('KZ', 'Kazakhstan', '+7', '🇰🇿'),
  Country('RU', 'Russia', '+7', '🇷🇺'),
  Country('UZ', 'Uzbekistan', '+998', '🇺🇿'),
  Country('KG', 'Kyrgyzstan', '+996', '🇰🇬'),
  Country('TJ', 'Tajikistan', '+992', '🇹🇯'),
  Country('TM', 'Turkmenistan', '+993', '🇹🇲'),
  Country('AZ', 'Azerbaijan', '+994', '🇦🇿'),
  Country('GE', 'Georgia', '+995', '🇬🇪'),
  Country('AM', 'Armenia', '+374', '🇦🇲'),
  Country('BY', 'Belarus', '+375', '🇧🇾'),
  Country('UA', 'Ukraine', '+380', '🇺🇦'),
  Country('TR', 'Türkiye', '+90', '🇹🇷'),
  Country('CN', 'China', '+86', '🇨🇳'),
  Country('AE', 'UAE', '+971', '🇦🇪'),
  Country('DE', 'Germany', '+49', '🇩🇪'),
  Country('GB', 'United Kingdom', '+44', '🇬🇧'),
  Country('US', 'United States', '+1', '🇺🇸'),
];

const defaultCountry = Country('KZ', 'Kazakhstan', '+7', '🇰🇿');

Country? countryByIso(String iso) {
  for (final c in countries) {
    if (c.iso == iso) return c;
  }
  return null;
}

String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// The national part of what someone typed, with a trunk prefix or a re-typed
/// country code removed.
///
/// Nobody in Almaty writes their mobile as "700 123 45 67". They write
/// "8 700 123 45 67", because 8 is what you dial domestically, or they paste
/// "+7 700 123 45 67" out of a contact card. Both were passed through as
/// digits and glued onto the dial code, producing +787001234567 and
/// +777001234567 — numbers that reach nobody. This is the phone number of an
/// emergency contact.
///
/// Two rules, and deliberately no more:
///
///   · A leading '+' means the digits that follow ARE the international form,
///     so a repeated country code is dropped.
///   · Otherwise a trunk prefix is dropped: '8' in the +7 zone, where the
///     national number is always ten digits, and one leading '0' elsewhere —
///     the trunk code across Europe and Central Asia, and no national number
///     begins with 0 anyway, so it is safe even where there is no trunk code.
///
/// It does NOT guess at a country code the user did not mark with a '+'.
/// German national numbers exist that begin 49 (4941 is Otterndorf), so
/// stripping a bare leading "49" from a German number would corrupt a real one.
/// Guessing there would trade a rare mistake for a rarer, more confident one.
String normalizeNational(String dial, String national) {
  final typedInternational = national.trimLeft().startsWith('+');
  var d = _digitsOnly(national);
  final cc = _digitsOnly(dial);

  if (typedInternational) {
    if (cc.isNotEmpty && d.length > cc.length && d.startsWith(cc)) d = d.substring(cc.length);
    return d;
  }
  if (cc == '7') {
    // KZ and RU national numbers are ten digits. Eleven starting with 8 is the
    // domestic form; eleven starting with 7 is the country code typed twice.
    if (d.length == 11 && (d.startsWith('8') || d.startsWith('7'))) return d.substring(1);
    return d;
  }
  if (d.length > 1 && d.startsWith('0')) return d.substring(1);
  return d;
}

/// Combine a dial code and a national number into E.164 (e.g. "+7", "700 123 45 67"
/// → "+77001234567"). Strips spaces/dashes/parens and any trunk prefix.
String toE164(String dial, String national) => dial + normalizeNational(dial, national);

/// A national number is plausible when it has 7–12 digits (covers the region).
///
/// Pass [dial] wherever it is known: it lets the check run on the number that
/// will actually be dialled rather than on the raw typing, and lets the +7 zone
/// insist on exactly ten digits. Without it, "8 700 123 45 67" passed as
/// eleven plausible digits and became an unreachable +7 number downstream.
bool isValidNationalNumber(String national, {String? dial}) {
  final digits = dial == null ? _digitsOnly(national) : normalizeNational(dial, national);
  final n = digits.length;
  if (dial != null && _digitsOnly(dial) == '7') return n == 10;
  return n >= 7 && n <= 12;
}

/// Light formatting for display: groups the national digits in 3-3-2-2 style.
String formatNational(String national) {
  final d = _digitsOnly(national);
  if (d.length < 4) return d;
  final b = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    if (i == 3 || i == 6 || i == 8) b.write(' ');
    b.write(d[i]);
  }
  return b.toString();
}
