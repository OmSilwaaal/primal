import Foundation
import SwiftData

@Model
final class FastingState {
    var id: UUID = UUID()
    var isFasting: Bool = false
    var startTime: Date?
    var targetDurationHours: Double = 16.0
    
    init(isFasting: Bool = false, startTime: Date? = nil, targetDurationHours: Double = 16.0) {
        self.isFasting = isFasting
        self.startTime = startTime
        self.targetDurationHours = targetDurationHours
    }
}
