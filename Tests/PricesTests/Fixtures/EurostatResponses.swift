// Recorded responses for Eurostat's dissemination API (JSON-stat 2.0).
//
// The build environment's network policy blocks ec.europa.eu, so these follow
// the documented JSON-stat 2.0 format of `prc_hicp_minr`, the HICP dataset
// that replaced `prc_hicp_midx` in 2026 (dimensions freq, unit, coicop18,
// geo, time). Index values are made up, consistent with the example library.

enum EurostatResponses {
    /// `GET prc_hicp_minr?format=JSON&lang=EN&coicop18=TOTAL&freq=M&geo=IT&unit=I15
    /// &sinceTimePeriod=2026-07&untilTimePeriod=2026-09`: September isn't published yet.
    static let hicpITJulyToSeptember = """
    {"version":"2.0","class":"dataset",\
    "label":"Harmonised index of consumer prices (HICP) - monthly data (index)","source":"ESTAT",\
    "updated":"2026-09-17T11:00:00+0200","value":{"0":128.1,"1":128.41},"status":{"1":"p"},\
    "id":["freq","unit","coicop18","geo","time"],"size":[1,1,1,1,2],\
    "dimension":{"freq":{"label":"Time frequency","category":{"index":{"M":0},"label":{"M":"Monthly"}}},\
    "unit":{"label":"Unit of measure","category":{"index":{"I15":0},"label":{"I15":"Index, 2015=100"}}},\
    "coicop18":{"label":"Classification of individual consumption by purpose (COICOP 2018)",\
    "category":{"index":{"TOTAL":0},"label":{"TOTAL":"All-items HICP"}}},\
    "geo":{"label":"Geopolitical entity (reporting)","category":{"index":{"IT":0},"label":{"IT":"Italy"}}},\
    "time":{"label":"Time","category":{"index":{"2026-07":0,"2026-08":1},\
    "label":{"2026-07":"2026-07","2026-08":"2026-08"}}}},\
    "extension":{"lang":"EN","agencyId":"ESTAT","id":"PRC_HICP_MINR","version":"1.0",\
    "datastructure":{"agencyId":"ESTAT","id":"PRC_HICP_MINR","version":"1.0"},\
    "annotation":[{"type":"OBS_COUNT","title":"2"},{"type":"OBS_PERIOD_OVERALL_OLDEST","title":"1996-01"},\
    {"type":"OBS_PERIOD_OVERALL_LATEST","title":"2026-08"}],\
    "positions-with-no-data":{"freq":[],"unit":[],"coicop18":[],"geo":[],"time":[]}}}
    """

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
