import Foundation
import OortLibrary
import ArcanePorting

enum UpstreamCheckState: Equatable {
    case idle
    case checking
    case loaded(UpstreamReview)
    case failed(String)
}
