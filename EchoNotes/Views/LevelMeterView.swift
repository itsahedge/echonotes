import SwiftUI

/// Visual representation of audio level (system or mic).
struct LevelMeterView: View {
    let label: String
    let level: Float
    
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(level > 0.5 ? Color.orange : Color.green)
                        .frame(width: geo.size.width * CGFloat(min(level * 4, 1.0)))
                        .animation(.linear(duration: 0.1), value: level)
                }
            }
            .frame(height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
