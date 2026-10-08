import Importer
import Model
import Tracker

extension ImportPreview {
    /// Applies the preview to `library`, then works out again the automatic
    /// flows of the library's valuations that now follow an inserted or
    /// changed value, as editing history does (UI.md, "New money after an
    /// inserted value"). Typed flows stay. The valuations touched are in the
    /// result, so they're backed up, written and undone with the import.
    func applyFollowingFlows(to library: Library) -> ImportResult {
        var result = apply(to: library)
        let flows = result.library.followFlows(from: library)
        result.followedFlows(flows.recomputed)
        return result
    }
}
