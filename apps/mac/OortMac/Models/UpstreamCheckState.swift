import Foundation
import OortLibrary
import NxnativeAdapter

enum UpstreamCheckState: Equatable {
    case idle
    case checking
    case loaded(UpstreamReview)
    case failed(String)
}
