/// Downloads a library's files before it's read, reporting progress.
///
/// Reading a file iCloud Drive hasn't downloaded yet (a coordinated read)
/// waits until it's downloaded, so reading a library that's only partly on
/// the device would download it one file at a time, with nothing to show
/// and no end if iCloud can't download. A downloader asks iCloud for every
/// missing file at once, and the library is read once they're all here.
///
/// Downloaders live on the main actor; stop one before dropping it.
@MainActor
public protocol LibraryDownloading: AnyObject {
    /// Starts (stopping a previous run first). Progress arrives on the
    /// stream, the latest first if it can't keep up. The stream finishes
    /// after a progress that ``LibraryDownloadProgress/isComplete``, or on
    /// ``stop()``. It can also finish without one if the download can't be
    /// followed; reading the library then downloads what's missing itself.
    func start() -> AsyncStream<LibraryDownloadProgress>

    /// Asks iCloud again for every file that hasn't arrived, forgetting
    /// failures, e.g. when the user chooses to keep waiting.
    func requestAgain()

    /// Stops following the download and finishes the stream. Downloads
    /// already asked for go on.
    func stop()
}

extension LibraryLocation {
    /// A downloader for this location: for a library in iCloud Drive on
    /// Apple platforms (`UbiquitousLibraryDownloader`); `nil` otherwise,
    /// where there's nothing to download.
    @MainActor
    public func makeDownloader() -> (any LibraryDownloading)? {
        #if canImport(Darwin)
        if isUbiquitous { return UbiquitousLibraryDownloader(root: url) }
        #endif
        return nil
    }
}
