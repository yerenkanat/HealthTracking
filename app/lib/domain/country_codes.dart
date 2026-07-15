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

/// Combine a dial code and a national number into E.164 (e.g. "+7", "700 123 45 67"
/// → "+77001234567"). Strips spaces/dashes/parens.
String toE164(String dial, String national) => dial + _digitsOnly(national);

/// A national number is plausible when it has 7–12 digits (covers the region).
bool isValidNationalNumber(String national) {
  final n = _digitsOnly(national).length;
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
