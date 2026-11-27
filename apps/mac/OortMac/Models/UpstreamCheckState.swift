import Foundation
import NXLibraryCore
import ArcanePorting

enum UpstreamCheckState: Equatable {
    case idle
    case checking
    case loaded(UpstreamReview)
    case failed(String)
}
