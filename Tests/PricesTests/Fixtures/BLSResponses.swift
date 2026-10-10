// Responses of the BLS public API, version 1, for the CPI-U series
// CUUR0000SA0.
//
// The build environment's network policy blocks api.bls.gov, so these follow
// the API's documented JSON format. Index values are made up.

enum BLSResponses {
    /// `GET timeseries/data/CUUR0000SA0?startyear=2025&endyear=2026`: July
    /// and August 2026 (September isn't published yet), a month without a
    /// value, and 2025's annual average, newest first as the API answers.
    static let twoYears = """
    {"status":"REQUEST_SUCCEEDED","responseTime":41,"message":[],"Results":{"series":[{"seriesID":"CUUR0000SA0",\
    "data":[\
    {"year":"2026","period":"M08","periodName":"August","latest":"true","value":"325.112","footnotes":[{}]},\
    {"year":"2026","period":"M07","periodName":"July","value":"324.804","footnotes":[{}]},\
    {"year":"2025","period":"M13","periodName":"Annual","value":"321.7","footnotes":[{}]},\
    {"year":"2025","period":"M12","periodName":"December","value":"321.950","footnotes":[{}]},\
    {"year":"2025","period":"M11","periodName":"November","value":"-",\
    "footnotes":[{"code":"X","text":"Data unavailable."}]},\
    {"year":"2025","period":"M10","periodName":"October","value":"322.4","footnotes":[{}]}\
    ]}]}}
    """

    /// One page of a long range: `startyear=2006&endyear=2015`, with only
    /// December 2015.
    static let olderPage = """
    {"status":"REQUEST_SUCCEEDED","responseTime":30,"message":[],"Results":{"series":[{"seriesID":"CUUR0000SA0",\
    "data":[{"year":"2015","period":"M12","periodName":"December","value":"236.525","footnotes":[{}]}]}]}}
    """

    /// The next page: `startyear=2016&endyear=2025`, with only January 2016.
    static let newerPage = """
    {"status":"REQUEST_SUCCEEDED","responseTime":30,"message":[],"Results":{"series":[{"seriesID":"CUUR0000SA0",\
    "data":[{"year":"2016","period":"M01","periodName":"January","value":"236.916","footnotes":[{}]}]}]}}
    """

    /// The daily limit of requests without a key is reached.
    static let notProcessed = """
    {"status":"REQUEST_NOT_PROCESSED","responseTime":12,"message":["Request could not be serviced, as the daily \
    threshold for total number of requests allocated to the user has been reached."],"Results":{}}
    """

    /// Another series than the one asked for.
    static let otherSeries = """
    {"status":"REQUEST_SUCCEEDED","responseTime":30,"message":[],"Results":{"series":[{"seriesID":"CUSR0000SA0",\
    "data":[{"year":"2026","period":"M08","periodName":"August","value":"325.0","footnotes":[{}]}]}]}}
    """
}
