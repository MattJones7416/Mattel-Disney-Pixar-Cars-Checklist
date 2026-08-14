import SwiftUI
#if os(macOS)
import AppKit
#endif

struct LoadingView: View {
    @State private var rotationDegrees = 0.0

    // Platform-safe colors
    private var platformBackground: Color {
        #if os(iOS) || targetEnvironment(macCatalyst)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
    private var platformGrayTrack: Color {
        #if os(iOS) || targetEnvironment(macCatalyst)
        Color(UIColor.systemGray5)
        #else
        Color(NSColor.systemGray)
        #endif
    }

    var body: some View {
        ZStack {
            platformBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // App Logo (replace with your actual logo)
                Image("app-logo") // Make sure to add this to your assets
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)

                // Animated loading indicator
                ZStack {
                    Circle()
                        .stroke(platformGrayTrack, lineWidth: 6)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.blue, .green]),
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(rotationDegrees))
                        .onAppear {
                            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                rotationDegrees = 360
                            }
                        }
                }

                // Loading text
                VStack(spacing: 8) {
                    Text("Loading Your Collection")
                        .font(.headline)

                    Text("Loading the die-cast catalogue…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}
