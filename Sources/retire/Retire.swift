import RetireCLI

/// The `retire` executable. The commands live in `RetireCLI`, where they're
/// tested; see `retire --help`.
@main
struct RetireMain {
    static func main() async {
        await Retire.main()
    }
}
