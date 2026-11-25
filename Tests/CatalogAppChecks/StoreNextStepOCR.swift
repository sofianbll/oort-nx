import Foundation
import Vision

func checkNextStepOCR(_ output: URL) throws {
    let cases: [(String, [String], [String])] = [
        ("online-app", ["app dans ton cloud", "telecharger l'app", "temps de jeu", "derniere partie", "plateforme", "aucune description"], []),
        ("offline-local", ["app sur ce mac", "jouer"], ["telecharger"]),
        ("offline-app", ["dernier emplacement connu", "app dans ton cloud"], []),
        ("reference-files", ["bibliotheque de reference", "telecharger les fichiers du jeu", "compile apres le telechargement"], []),
        ("local-files", ["fichiers du jeu sur ce mac", "compiler"], []),
        ("engine-blocked", ["verifie le moteur avant de compiler"], []),
        ("offline-cache", ["cloud indisponible"], ["telecharger", "jouer", "localise"]),
        ("cache-only", ["localise tes fichiers"], ["telecharger", "jouer"]),
        ("unchecked", ["cloud non verifie"], ["telecharger", "localise"]),
        ("running", ["telechargement de l'app", "42"], ["telecharger"]),
        ("verifying", ["verification de l'app"], ["telecharger"]),
        ("waiting", ["en attente de la fermeture du jeu"], ["telecharger"]),
        ("queued", ["en attente"], ["telecharger"]),
        ("refreshing", ["verification"], ["telecharger"]),
        ("blocked", ["telechargement indisponible"], ["telecharger"]),
    ]
    for (state, expected, unexpected) in cases {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["fr-FR"]
        try VNImageRequestHandler(url: output.appendingPathComponent(state + "-1120.png")).perform([request])
        let screen = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr"))
            .replacingOccurrences(of: "’", with: "'")
        let missing = expected.filter { !screen.contains($0) }
        let found = unexpected.filter { screen.contains($0) }
        guard missing.isEmpty && found.isEmpty else {
            FileHandle.standardError.write(Data("\(state): missing \(missing); unexpected \(found)\n\(screen)\n".utf8))
            exit(1)
        }
    }
}
