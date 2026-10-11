// Responses of the ONS time-series download for the CPI series D7BT (MM23).
//
// The build environment's network policy blocks www.ons.gov.uk, so these
// follow the download's CSV layout: rows about the series, then yearly,
// quarterly and monthly values. Index values are made up.

enum ONSResponses {
    /// `GET generator?format=csv&uri=/economy/inflationandpriceindices/timeseries/d7bt/mm23`:
    /// 2025 and 2026 through August, with Windows line ends.
    static let series = [
        #""Title","CPI INDEX 00: ALL ITEMS 2015=100""#,
        #""CDID","D7BT""#,
        #""Source dataset ID","MM23""#,
        #""PreUnit","""#,
        #""Unit","2015=100""#,
        #""Release date","16-09-2026""#,
        #""Next release","21 October 2026""#,
        #""Important notes","""#,
        #""2025","138.4""#,
        #""2025 Q3","138.9""#,
        #""2025 Q4","139.5""#,
        #""2026 Q1","140.1""#,
        #""2026 Q2","141.6""#,
        #""2025 OCT","139.2""#,
        #""2025 NOV","139.4""#,
        #""2025 DEC","139.9""#,
        #""2026 JUL","142.0""#,
        #""2026 AUG","142.3""#,
    ].joined(separator: "\r\n") + "\r\n"

    /// Another series than D7BT.
    static let otherSeries = """
    "Title","CPIH INDEX 00: ALL ITEMS 2015=100"
    "CDID","L522"
    "2026 AUG","141.0"
    """

    /// A page that isn't the series, e.g. an error page answered with 200.
    static let notTheSeries = "<!DOCTYPE html><html><body>Service unavailable</body></html>"
}
