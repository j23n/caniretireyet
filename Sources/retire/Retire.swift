#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import RetireCLI

/// The `retire` executable. The commands live in `RetireCLI`, where they're
/// tested; see `retire --help`.
@main
struct RetireMain {
    static func main() async {
        exit(await RetireCLI.run(context: .live()))
    }
}
