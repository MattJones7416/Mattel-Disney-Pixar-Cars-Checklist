import SwiftUI

extension MetalModel {
    var statusColor: Color {
        switch statusEnum {
        case .retired: return .red
        case .exclusive: return .blue
        case .comingSoon: return .green
        case .none: return .primary
        }
    }
}
