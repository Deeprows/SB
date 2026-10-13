/// Country (ISO 3166 alpha-2) -> currency (ISO 4217), used to show the
/// Premium price in the person's own money. Anything not listed falls back
/// to US dollars. The Worker does the conversion; this only picks the code.
const Map<String, String> _currencyByCountry = {
  // Africa
  'NG': 'NGN', 'GH': 'GHS', 'KE': 'KES', 'ZA': 'ZAR', 'UG': 'UGX',
  'TZ': 'TZS', 'RW': 'RWF', 'ET': 'ETB', 'EG': 'EGP', 'MA': 'MAD',
  'DZ': 'DZD', 'TN': 'TND', 'ZM': 'ZMW', 'ZW': 'USD', 'MW': 'MWK',
  'MZ': 'MZN', 'AO': 'AOA', 'NA': 'NAD', 'BW': 'BWP', 'LR': 'LRD',
  'SL': 'SLE', 'GM': 'GMD', 'CD': 'CDF', 'MU': 'MUR', 'SD': 'SDG',
  'LY': 'LYD', 'SN': 'XOF', 'CI': 'XOF', 'ML': 'XOF', 'BF': 'XOF',
  'BJ': 'XOF', 'TG': 'XOF', 'NE': 'XOF', 'GW': 'XOF', 'CM': 'XAF',
  'GA': 'XAF', 'CG': 'XAF', 'TD': 'XAF', 'GQ': 'XAF', 'CF': 'XAF',
  // Europe
  'GB': 'GBP', 'CH': 'CHF', 'SE': 'SEK', 'NO': 'NOK', 'DK': 'DKK',
  'PL': 'PLN', 'CZ': 'CZK', 'HU': 'HUF', 'RO': 'RON', 'BG': 'BGN',
  'TR': 'TRY', 'UA': 'UAH', 'RU': 'RUB', 'IS': 'ISK',
  'DE': 'EUR', 'FR': 'EUR', 'ES': 'EUR', 'IT': 'EUR', 'NL': 'EUR',
  'BE': 'EUR', 'PT': 'EUR', 'IE': 'EUR', 'AT': 'EUR', 'FI': 'EUR',
  'GR': 'EUR', 'HR': 'EUR', 'SK': 'EUR', 'SI': 'EUR', 'LU': 'EUR',
  // Americas
  'US': 'USD', 'CA': 'CAD', 'MX': 'MXN', 'BR': 'BRL', 'AR': 'ARS',
  'CL': 'CLP', 'CO': 'COP', 'PE': 'PEN', 'JM': 'JMD', 'TT': 'TTD',
  // Asia / Middle East / Oceania
  'IN': 'INR', 'PK': 'PKR', 'BD': 'BDT', 'LK': 'LKR', 'NP': 'NPR',
  'CN': 'CNY', 'JP': 'JPY', 'KR': 'KRW', 'ID': 'IDR', 'MY': 'MYR',
  'SG': 'SGD', 'TH': 'THB', 'VN': 'VND', 'PH': 'PHP', 'HK': 'HKD',
  'AE': 'AED', 'SA': 'SAR', 'QA': 'QAR', 'KW': 'KWD', 'BH': 'BHD',
  'OM': 'OMR', 'IL': 'ILS', 'JO': 'JOD', 'LB': 'LBP', 'IQ': 'IQD',
  'AU': 'AUD', 'NZ': 'NZD',
};

/// Currency code for a country code ('NG' -> 'NGN'). Unknown or missing
/// countries get 'USD'.
String currencyForCountry(String? countryCode) {
  final c = (countryCode ?? '').toUpperCase();
  return _currencyByCountry[c] ?? 'USD';
}
