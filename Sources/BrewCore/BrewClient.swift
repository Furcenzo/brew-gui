import Foundation

// MARK: - JSON modely z `brew info --json=v2`

public struct FormulaInfo: Decodable, Sendable, Hashable {
    public struct Versions: Decodable, Sendable, Hashable { public var stable: String? }
    public struct Installed: Decodable, Sendable, Hashable {
        public var version: String
        public var installedOnRequest: Bool?
    }

    public var name: String
    public var fullName: String
    public var desc: String?
    public var homepage: String?
    public var license: String?
    public var tap: String?
    public var aliases: [String]?
    public var oldnames: [String]?
    public var versions: Versions
    public var installed: [Installed]
    public var dependencies: [String]?
    public var caveats: String?
    public var outdated: Bool?
    public var pinned: Bool?
    public var kegOnly: Bool?
    public var deprecated: Bool?
    public var deprecationReason: String?
    public var deprecationReplacementFormula: String?
    public var deprecationReplacementCask: String?
    public var disabled: Bool?
    public var disableReason: String?

    public var installedVersion: String? { installed.last?.version }
    public var isInstalledOnRequest: Bool { installed.contains { $0.installedOnRequest == true } }

    public var lifecycleWarning: String? {
        Deprecation.warning(
            deprecated: deprecated, reason: deprecationReason, disabled: disabled, disableReason: disableReason,
            replacement: deprecationReplacementFormula ?? deprecationReplacementCask
        )
    }
}

/// Text upozornenia pre balíky, ktoré Homebrew označil ako deprecated / disabled.
enum Deprecation {
    static func warning(deprecated: Bool?, reason: String?, disabled: Bool?, disableReason: String?, replacement: String?) -> String? {
        let isDisabled = disabled == true
        guard isDisabled || deprecated == true else { return nil }
        var text = isDisabled ? "Vypnuté v Homebrew" : "Nepodporované (deprecated)"
        if let why = (isDisabled ? disableReason : reason).map(translate), !why.isEmpty { text += ": \(why)" }
        if let replacement, !replacement.isEmpty { text += ". Náhrada: \(replacement)" }
        return text
    }

    static func translate(_ reason: String) -> String {
        switch reason {
        case "unmaintained", "is not maintained upstream": "projekt sa už nevyvíja"
        case "discontinued": "projekt bol ukončený"
        case "does_not_build": "nedá sa zostaviť"
        case "repo_archived": "repozitár je archivovaný"
        case "repo_removed": "repozitár bol odstránený"
        case "no_license": "chýba licencia"
        case "checksum_mismatch": "nesedí kontrolný súčet"
        case "fails_gatekeeper_check": "neprejde kontrolou Gatekeeper"
        case "unsigned": "aplikácia nie je podpísaná"
        case "versioned_formula": "verzovaná formula už nie je podporovaná"
        default: reason.replacingOccurrences(of: "_", with: " ")
        }
    }
}

public struct CaskInfo: Decodable, Sendable, Hashable {
    public var token: String
    public var fullToken: String
    public var name: [String]?
    public var desc: String?
    public var homepage: String?
    public var tap: String?
    public var version: String?
    public var installed: String?
    public var oldTokens: [String]?
    public var caveats: String?
    public var outdated: Bool?
    public var autoUpdates: Bool?
    public var deprecated: Bool?
    public var deprecationReason: String?
    public var deprecationReplacementCask: String?
    public var deprecationReplacementFormula: String?
    public var disabled: Bool?
    public var disableReason: String?

    public var lifecycleWarning: String? {
        Deprecation.warning(
            deprecated: deprecated, reason: deprecationReason, disabled: disabled, disableReason: disableReason,
            replacement: deprecationReplacementCask ?? deprecationReplacementFormula
        )
    }
}

struct InfoResponse: Decodable {
    var formulae: [FormulaInfo]
    var casks: [CaskInfo]
}

/// Detail balíka pre panel s informáciami.
public enum PackageInfo: Sendable, Hashable {
    case formula(FormulaInfo)
    case cask(CaskInfo)

    public var displayName: String {
        switch self {
        case .formula(let f): f.name
        case .cask(let c): c.name?.first ?? c.token
        }
    }
    public var token: String {
        switch self {
        case .formula(let f): f.fullName
        case .cask(let c): c.fullToken
        }
    }
    public var desc: String? {
        switch self {
        case .formula(let f): f.desc
        case .cask(let c): c.desc
        }
    }
    public var homepage: URL? {
        switch self {
        case .formula(let f): f.homepage.flatMap(URL.init(string:))
        case .cask(let c): c.homepage.flatMap(URL.init(string:))
        }
    }
    public var latestVersion: String? {
        switch self {
        case .formula(let f): f.versions.stable
        case .cask(let c): c.version
        }
    }
    public var installedVersion: String? {
        switch self {
        case .formula(let f): f.installedVersion
        case .cask(let c): c.installed
        }
    }
    public var caveats: String? {
        switch self {
        case .formula(let f): f.caveats
        case .cask(let c): c.caveats
        }
    }
    public var tap: String? {
        switch self {
        case .formula(let f): f.tap
        case .cask(let c): c.tap
        }
    }
    public var kind: EntryKind {
        switch self {
        case .formula: .brew
        case .cask: .cask
        }
    }
    public var lifecycleWarning: String? {
        switch self {
        case .formula(let f): f.lifecycleWarning
        case .cask(let c): c.lifecycleWarning
        }
    }
}

// MARK: - Outdated

public struct OutdatedPackage: Decodable, Sendable, Hashable, Identifiable {
    public var name: String
    public var installedVersions: [String]
    public var currentVersion: String
    public var pinned: Bool?
    public var isCask: Bool = false

    public var id: String { (isCask ? "cask:" : "brew:") + name }
    public var installedVersion: String { installedVersions.joined(separator: ", ") }

    enum CodingKeys: String, CodingKey { case name, installedVersions, currentVersion, pinned }
}

struct OutdatedResponse: Decodable {
    var formulae: [OutdatedPackage]
    var casks: [OutdatedPackage]
}

// MARK: - Stav inštalácie

/// Prehľad nainštalovaných balíkov – indexovaný podľa všetkých mien a aliasov.
public struct InstalledState: Sendable {
    public var formulae: [FormulaInfo] = []
    public var casks: [CaskInfo] = []
    public var taps: Set<String> = []
    /// `nil`, ak `mas` nie je nainštalovaný.
    public var masApps: [String: MasApp]?

    private var formulaIndex: [String: FormulaInfo] = [:]
    private var caskIndex: [String: CaskInfo] = [:]

    public init() {}

    init(formulae: [FormulaInfo], casks: [CaskInfo], taps: Set<String>, masApps: [String: MasApp]?) {
        self.formulae = formulae
        self.casks = casks
        self.taps = taps
        self.masApps = masApps
        for formula in formulae {
            for key in [formula.name, formula.fullName] + (formula.aliases ?? []) + (formula.oldnames ?? []) {
                formulaIndex[key.lowercased()] = formula
            }
        }
        for cask in casks {
            for key in [cask.token, cask.fullToken] + (cask.oldTokens ?? []) {
                caskIndex[key.lowercased()] = cask
            }
        }
    }

    public func formula(named name: String) -> FormulaInfo? {
        Self.lookup(name, in: formulaIndex)
    }

    public func cask(named name: String) -> CaskInfo? {
        Self.lookup(name, in: caskIndex)
    }

    /// `user/tap/foo` musí sedieť presne – inak by sa `frankea/whisky/whisky` zamenil s oficiálnym `whisky`.
    /// Krátky názov skúšame len pri oficiálnych tapoch (`homebrew/cask/foo`).
    static func lookup<T>(_ name: String, in index: [String: T]) -> T? {
        let key = name.lowercased()
        if let exact = index[key] { return exact }
        let parts = key.split(separator: "/")
        guard parts.count == 3, parts[0] == "homebrew" else { return nil }
        return index[String(parts[2])]
    }

    public func lifecycleWarning(of entry: BrewfileEntry) -> String? {
        switch entry.kind {
        case .brew: formula(named: entry.name)?.lifecycleWarning
        case .cask: cask(named: entry.name)?.lifecycleWarning
        default: nil
        }
    }

    public func hasTap(_ name: String) -> Bool {
        let key = name.lowercased()
        // Oficiálne tapy (homebrew/core, homebrew/cask…) sa dnes riešia cez API a `brew tap` ich nevypisuje.
        return taps.contains(key) || key.hasPrefix("homebrew/")
    }

    public func status(of entry: BrewfileEntry) -> EntryStatus {
        switch entry.kind {
        case .brew:
            guard let f = formula(named: entry.name), let installed = f.installedVersion else { return .missing }
            return f.outdated == true ? .outdated(installed: installed, latest: f.versions.stable) : .installed(installed)
        case .cask:
            guard let c = cask(named: entry.name), let installed = c.installed else { return .missing }
            return c.outdated == true ? .outdated(installed: installed, latest: c.version) : .installed(installed)
        case .tap:
            return hasTap(entry.name) ? .installed(nil) : .missing
        case .mas:
            guard let masApps else { return .unknown }
            guard let id = entry.masID else { return .unknown }
            return masApps[id].map { .installed($0.version) } ?? .missing
        default:
            return .unknown
        }
    }

    public func description(of entry: BrewfileEntry) -> String? {
        switch entry.kind {
        case .brew: formula(named: entry.name)?.desc
        case .cask: cask(named: entry.name)?.desc
        default: nil
        }
    }
}

/// Aplikácia z Mac App Store podľa `mas list`.
public struct MasApp: Sendable, Hashable {
    public var id: String
    public var name: String
    public var version: String

    /// Riadky v tvare `682658836  GarageBand  (10.4.14)`.
    public static func parseList(_ output: String) -> [String: MasApp] {
        var result: [String: MasApp] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let space = text.firstIndex(of: " ") else { continue }
            let id = String(text[..<space])
            guard id.allSatisfy(\.isNumber) else { continue }
            var rest = text[space...].trimmingCharacters(in: .whitespaces)
            var version = ""
            if rest.hasSuffix(")"), let open = rest.lastIndex(of: "(") {
                version = String(rest[rest.index(after: open)..<rest.index(before: rest.endIndex)])
                rest = rest[..<open].trimmingCharacters(in: .whitespaces)
            }
            result[id] = MasApp(id: id, name: rest.isEmpty ? id : rest, version: version)
        }
        return result
    }
}

public enum EntryStatus: Sendable, Hashable {
    case installed(String?)
    case outdated(installed: String, latest: String?)
    case missing
    case unknown

    public var sortOrder: Int {
        switch self {
        case .missing: 0
        case .outdated: 1
        case .installed: 2
        case .unknown: 3
        }
    }

    public var installedVersion: String? {
        switch self {
        case .installed(let v): v
        case .outdated(let v, _): v
        default: nil
        }
    }

    public var isInstalled: Bool {
        switch self {
        case .installed, .outdated: true
        default: false
        }
    }
}

/// Výsledok `brew bundle cleanup` bez `--force`.
public struct CleanupPreview: Sendable, Hashable {
    public var casks: [String] = []
    public var formulae: [String] = []
    public var taps: [String] = []
    public var other: [String] = []

    public var isEmpty: Bool { casks.isEmpty && formulae.isEmpty && taps.isEmpty && other.isEmpty }

    public init() {}

    public init(parsing output: String) {
        enum Section { case casks, formulae, taps, other, none }
        var section = Section.none
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("would uninstall casks") { section = .casks; continue }
            if lower.hasPrefix("would uninstall formulae") { section = .formulae; continue }
            if lower.hasPrefix("would untap") { section = .taps; continue }
            if lower.hasPrefix("would `brew cleanup`") || lower.hasPrefix("would ") && line.hasSuffix(":") { section = .other; continue }
            if lower.hasPrefix("run `brew bundle cleanup --force`") { continue }
            switch section {
            case .casks: casks.append(line)
            case .formulae: formulae.append(line)
            case .taps: taps.append(line)
            case .other: other.append(line)
            case .none: break
            }
        }
    }
}

// MARK: - Klient

/// Tenký obal nad `brew` CLI.
public struct BrewClient: Sendable {
    public let brewURL: URL

    public init(brewURL: URL) {
        self.brewURL = brewURL
    }

    public static func locate() -> BrewClient? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/home/linuxbrew/.linuxbrew/bin/brew"]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { BrewClient(brewURL: URL(fileURLWithPath: $0)) }
    }

    public var prefixBin: String { brewURL.deletingLastPathComponent().path }

    /// Prostredie pre brew. GUI aplikácie nededia PATH zo shellu, preto ho skladáme ručne.
    public func environment(quiet: Bool, askpass: URL? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let path = [prefixBin, "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = (path + (env["PATH"]?.split(separator: ":").map(String.init) ?? []))
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ":")
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_EMOJI"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        env["NO_COLOR"] = "1"
        if quiet { env["HOMEBREW_NO_AUTO_UPDATE"] = "1" }
        if let askpass { env["SUDO_ASKPASS"] = askpass.path }
        return env
    }

    public func capture(_ arguments: [String], allowFailure: Bool = false) async throws -> String {
        try await ProcessRunner.capture(
            executable: brewURL,
            arguments: arguments,
            environment: environment(quiet: true),
            allowFailure: allowFailure
        )
    }

    public func stream(_ arguments: [String], askpass: URL? = nil) -> AsyncThrowingStream<ProcessEvent, Error> {
        ProcessRunner.stream(
            executable: brewURL,
            arguments: arguments,
            environment: environment(quiet: false, askpass: askpass),
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    public func installedState() async throws -> InstalledState {
        async let infoText = capture(["info", "--json=v2", "--installed"])
        async let tapText = capture(["tap"])
        async let mas = masApps()
        let info = try Self.decoder.decode(InfoResponse.self, from: Data(try await infoText.utf8))
        let taps = Set(try await tapText.split(whereSeparator: \.isNewline).map { $0.lowercased() })
        return InstalledState(formulae: info.formulae, casks: info.casks, taps: taps, masApps: await mas)
    }

    /// ID → aplikácia z App Store (cez `mas list`).
    func masApps() async -> [String: MasApp]? {
        let mas = brewURL.deletingLastPathComponent().appendingPathComponent("mas")
        guard FileManager.default.isExecutableFile(atPath: mas.path) else { return nil }
        guard let output = try? await ProcessRunner.capture(executable: mas, arguments: ["list"], environment: environment(quiet: true)) else { return nil }
        return MasApp.parseList(output)
    }

    public func outdated(greedy: Bool) async throws -> [OutdatedPackage] {
        var args = ["outdated", "--json=v2"]
        if greedy { args.append("--greedy") }
        // `brew outdated` vracia nenulový kód, keď niečo zastarané existuje.
        let text = try await capture(args, allowFailure: true)
        let response = try Self.decoder.decode(OutdatedResponse.self, from: Data(text.utf8))
        return response.formulae + response.casks.map { var c = $0; c.isCask = true; return c }
    }

    public func allNames() async throws -> (formulae: [String], casks: [String]) {
        async let formulae = capture(["formulae"])
        async let casks = capture(["casks"])
        let split: (String) -> [String] = { $0.split(whereSeparator: \.isNewline).map(String.init) }
        return (split(try await formulae), split(try await casks))
    }

    public func info(kind: EntryKind, name: String) async throws -> PackageInfo {
        let args = ["info", "--json=v2", kind == .cask ? "--cask" : "--formula", name]
        let text = try await capture(args)
        let response = try Self.decoder.decode(InfoResponse.self, from: Data(text.utf8))
        if let formula = response.formulae.first { return .formula(formula) }
        if let cask = response.casks.first { return .cask(cask) }
        throw CommandError(command: "brew " + args.joined(separator: " "), status: 0, stderr: "Balík sa nenašiel.")
    }

    public func cleanupPreview(file: URL) async throws -> CleanupPreview {
        let text = try await capture(["bundle", "cleanup", "--file=\(file.path)"], allowFailure: true)
        return CleanupPreview(parsing: text)
    }
}
