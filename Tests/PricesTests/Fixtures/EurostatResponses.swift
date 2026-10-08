// Recorded responses for Eurostat's dissemination API (JSON-stat 2.0).
//
// The build environment's network policy blocks ec.europa.eu, so these follow
// the documented JSON-stat 2.0 format of `prc_hicp_minr`, the HICP dataset
// that replaced `prc_hicp_midx` in 2026 (dimensions freq, unit, coicop18,
// geo, time). Index values are made up, consistent with the example library.
// Italy's July and August 2026, which the CLI's tests use too, are
// TestSupport's `PriceResponses`.

enum EurostatResponses {
    /// A sparse series in the older style: values as an array with a null,
    /// time codes as an array, `2025M10` labels, and no index for
    /// single-category dimensions.
    static let arrayStyle = """
    {"version":"2.0","class":"dataset","value":[126.1,null,126.3],\
    "id":["freq","unit","coicop18","geo","time"],"size":[1,1,1,1,3],\
    "dimension":{"freq":{"category":{"label":{"M":"Monthly"}}},"unit":{"category":{"label":{"I15":"Index"}}},\
    "coicop18":{"category":{"label":{"TOTAL":"All-items HICP"}}},"geo":{"category":{"label":{"IT":"Italy"}}},\
    "time":{"category":{"index":["2025M10","2025M11","2025M12"]}}}}
    """

    /// A dataset with two countries: not a single series.
    static let twoCountries = """
    {"version":"2.0","class":"dataset","value":{"0":128.1,"1":127.2},\
    "id":["freq","unit","coicop18","geo","time"],"size":[1,1,1,2,1],\
    "dimension":{"geo":{"category":{"index":{"IT":0,"FR":1}}},"time":{"category":{"index":{"2026-07":0}}}}}
    """

    /// 400 for an invalid filter.
    static let badFilter = """
    {"error":{"status":"400","id":"100","label":"Invalid filter value: unit=I99"}}
    """
}
