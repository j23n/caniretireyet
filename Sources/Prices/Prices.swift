/// # Prices
///
/// Price and FX providers.
///
/// - FX: ECB reference rates through Frankfurter.
/// - Crypto: CoinGecko or an exchange's public ticker.
/// - Gold and silver: a spot-price API, converted to the instrument's unit
///   (e.g. USD per troy ounce → EUR per gram).
/// - ETFs: Yahoo Finance's public chart endpoint, with pluggable paid
///   providers.
/// - Inflation indices (Eurostat HICP).
///
/// Providers are chosen by an instrument's `priceSource.provider` and return
/// `Model.PriceRecord`, `FXRecord` and `IndexRecord` values. Only instrument
/// symbols ever leave the device.
///
/// Placeholder: this module is owned by another engineer.
enum PricesModule {}
