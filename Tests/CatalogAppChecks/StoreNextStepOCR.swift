import Foundation
import Vision

func checkNextStepOCR(_ output: URL) throws {
    let url = output.appendingPathComponent("online-app-1120.png")
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["fr-FR"]
    try VNImageRequestHandler(url: url).perform([request])
    let remote = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr"))
    guard remote.contains("app dans votre cloud") else {
        FileHandle.standardError.write(Data("Details does not show the app's cloud origin:\n\(remote)\n".utf8))
        exit(1)
    }
}
