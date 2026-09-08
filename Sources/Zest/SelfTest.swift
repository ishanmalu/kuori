import Foundation

/// `Zest --selftest` runs the checks that must hold for the conversion graph to
/// be coherent, then exits non-zero on any failure. XCTest isn't in the Command
/// Line Tools SDK, so tests ship in the binary and run anywhere, including CI
/// where no engines are installed.
enum SelfTest {
    private static var failures: [String] = []
    private static var passCount = 0

    private static func expect(_ cond: Bool, _ what: String) {
        if cond { passCount += 1; print("  ok   \(what)") }
        else { failures.append(what); print("  FAIL \(what)") }
    }

    private static func section(_ name: String) { print("\n\(name)") }

    static func run() -> Never {
        print("Zest self-test\n")

        section("format resolution")
        expect(Formats.byExtension("jpeg")?.id == "jpg", "jpeg alias -> jpg")
        expect(Formats.byExtension(".PNG")?.id == "png", "case/dot-insensitive")
        expect(Formats.byExtension("tgz")?.id == "targz", "tgz alias -> targz")
        expect(Formats.byURL(URL(fileURLWithPath: "/x/a.tar.gz"))?.id == "targz", "double extension")
        expect(Formats.byURL(URL(fileURLWithPath: "/x/y.bogus")) == nil, "unknown extension -> nil")

        section("capability graph")
        let jpg = Formats.byID["jpg"]!, png = Formats.byID["png"]!
        let mp4 = Formats.byID["mp4"]!, mp3 = Formats.byID["mp3"]!, gif = Formats.byID["gif"]!
        let folder = Formats.byID["folder"]!, zip = Formats.byID["zip"]!
        expect(Engine.targets(for: jpg).contains(png), "jpg -> png offered")
        expect(!Engine.targets(for: jpg).contains(jpg), "no identity route")
        expect(Engine.targets(for: mp4).contains(mp3), "mp4 -> mp3 offered")
        expect(Engine.targets(for: mp4).contains(gif), "mp4 -> gif offered")
        expect(Engine.targets(for: folder).contains(zip), "folder -> zip offered")
        expect(Engine.targets(for: zip).contains(folder), "zip -> folder offered")
        expect(Engine.converter(from: mp4, to: mp3) is MediaConverter, "mp4->mp3 routes to MediaConverter")
        expect(Engine.converter(from: jpg, to: Formats.byID["pdf"]!) is PDFConverter, "jpg->pdf routes to PDFConverter")

        section("argument builders")
        let dummyIn = URL(fileURLWithPath: "/tmp/in.mp4")
        let dummyOut = URL(fileURLWithPath: "/tmp/out.mp3")
        if let inv = try? MediaConverter().plan(input: dummyIn, from: mp4, to: mp3,
                                                output: dummyOut, opts: ConvertOptions()) {
            expect(inv.args.contains("libmp3lame"), "mp3 plan uses libmp3lame")
            expect(inv.args.contains("-vn"), "mp3 plan drops video")
        } else { expect(false, "mp4->mp3 plan built") }

        if let inv = try? MediaConverter().plan(input: dummyIn, from: mp4, to: gif,
                                                output: URL(fileURLWithPath: "/tmp/o.gif"),
                                                opts: ConvertOptions(scale: "600x")) {
            expect(inv.args.joined().contains("palettegen"), "gif plan uses palette")
            expect(inv.args.joined().contains("scale=600"), "gif plan honors --scale")
        } else { expect(false, "mp4->gif plan built") }

        if let inv = try? ArchiveConverter().plan(input: URL(fileURLWithPath: "/tmp/dir"),
                                                  from: folder, to: zip,
                                                  output: URL(fileURLWithPath: "/tmp/dir.zip"),
                                                  opts: ConvertOptions()) {
            expect(inv.engine == .bsdtar && inv.args.contains("-a"), "folder->zip uses bsdtar -a")
        } else { expect(false, "folder->zip plan built") }

        expect((try? ArchiveConverter().plan(input: URL(fileURLWithPath: "/tmp/d"),
                                             from: folder, to: Formats.byID["rar"]!,
                                             output: URL(fileURLWithPath: "/tmp/d.rar"),
                                             opts: ConvertOptions())) == nil,
               "RAR creation is refused")

        section("output naming")
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("zest-selftest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let srcA = tmp.appendingPathComponent("photo.png")
        FileManager.default.createFile(atPath: srcA.path, contents: Data("x".utf8))
        let o1 = Naming.output(for: srcA, target: jpg, into: nil, collision: .suffix)
        expect(o1?.lastPathComponent == "photo.jpg", "first output has no suffix")
        FileManager.default.createFile(atPath: o1!.path, contents: Data("x".utf8))
        let o2 = Naming.output(for: srcA, target: jpg, into: nil, collision: .suffix)
        expect(o2?.lastPathComponent == "photo 2.jpg", "collision bumps to ' 2'")
        expect(Naming.output(for: srcA, target: jpg, into: nil, collision: .skip) == nil, "skip returns nil when target exists")
        let srcB = tmp.appendingPathComponent("fresh.png")
        FileManager.default.createFile(atPath: srcB.path, contents: Data("x".utf8))
        expect(Naming.output(for: srcB, target: jpg, into: nil, collision: .skip) != nil, "skip returns a path when clear")
        expect(Naming.output(for: srcA, target: jpg, into: nil, collision: .overwrite)?.lastPathComponent == "photo.jpg",
               "overwrite reuses the existing name")

        section("engine availability (informational)")
        for id in [EngineID.ffmpeg, .vips, .resvg, .potrace, .pandoc, .qpdf, .sevenzip, .unar, .bsdtar, .exiftool] {
            let where_ = EngineLocator.path(for: id) ?? "— not found (bundle or brew install)"
            print("  \(id.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(where_)")
        }

        print("")
        if failures.isEmpty {
            print("PASS — \(passCount) checks")
            exit(0)
        } else {
            print("FAIL — \(failures.count) of \(passCount + failures.count):")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }
}
