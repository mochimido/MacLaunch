import AppKit

struct ApplicationEntry: Equatable {
    let name: String
    let url: URL
}

enum RegistrationSource {
    static func item(from original: URL) -> LaunchItem? {
        var url = original
        if url.isFileURL {
            if (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true,
               let resolved = try? URL(resolvingAliasFileAt: url, options: [.withoutUI]) { url = resolved }
            if url.pathExtension.lowercased() == "webloc",
               let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let raw = plist["URL"] as? String, let link = URL(string: raw) { url = link }
        }
        guard let target = LaunchItem.validTarget(url.isFileURL ? url.path : url.absoluteString) else { return nil }
        var name = url.isFileURL ? FileManager.default.displayName(atPath: url.path) : (url.host ?? url.absoluteString)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        return LaunchItem(name: String(name.prefix(80)), target: target)
    }

    static func url(from text: String, assumeHTTPS: Bool = false) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\"") && value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
        if assumeHTTPS, !value.contains(":"), !value.hasPrefix("/"), !value.hasPrefix("~"), value.contains("."), !value.contains(" ") {
            value = "https://" + value
        }
        guard let target = LaunchItem.validTarget(value) else { return nil }
        return LaunchItem(name: "", target: target).url
    }

    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty { return urls }
        guard let text = pasteboard.string(forType: .string) else { return [] }
        return text.components(separatedBy: .newlines).compactMap { url(from: $0) }
    }

    static var runningApplications: [ApplicationEntry] {
        NSWorkspace.shared.runningApplications.compactMap { app -> ApplicationEntry? in
            guard app.activationPolicy == .regular, let url = app.bundleURL else { return nil }
            return ApplicationEntry(name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, url: url)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static var commonFolders: [(String, URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [("ホーム", home), ("デスクトップ", home.appendingPathComponent("Desktop")),
                ("書類", home.appendingPathComponent("Documents")), ("ダウンロード", home.appendingPathComponent("Downloads")),
                ("アプリケーション", URL(fileURLWithPath: "/Applications"))]
    }

    static func applications(in roots: [URL]? = nil) -> [ApplicationEntry] {
        let directories = roots ?? [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [String: ApplicationEntry] = [:]
        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() == "app" {
                    let canonical = url.standardizedFileURL.path
                    found[canonical] = ApplicationEntry(name: String(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "").prefix(80)), url: url)
                    enumerator.skipDescendants()
                } else if enumerator.level >= 2 { enumerator.skipDescendants() }
            }
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
