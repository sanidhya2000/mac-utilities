import SwiftUI

/// Fullscreen calibration surface. Only the screen currently being calibrated
/// draws the dot; the rest show a short instruction so the user knows the
/// process has not stalled.
struct CalibrationScreenView: View {
    @ObservedObject var controller: CalibrationController
    let screenID: String

    private var isActive: Bool { controller.activeScreenID == screenID }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if isActive {
                    CalibrationDot(isSampling: controller.dotIsSampling)
                        .position(x: controller.dotPosition.x,
                                  y: geometry.size.height - controller.dotPosition.y)

                    VStack(spacing: 10) {
                        Text("Look at the dot")
                            .font(.system(size: 22, weight: .medium))
                        Text("Turn your head toward it, not just your eyes.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(controller.faceVisible ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(controller.faceVisible ? "Face detected" : "Looking for your face…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)

                        ProgressView(value: controller.progress)
                            .frame(width: 220)
                            .padding(.top, 8)

                        Text("Press Esc to cancel")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 70)
                } else {
                    Text("Calibrating \(controller.currentScreenName)…")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .ignoresSafeArea()
        .onExitCommand { controller.cancel() }
    }
}

/// Pulses while sampling so the user knows to hold still.
private struct CalibrationDot: View {
    let isSampling: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 2)
                .frame(width: isSampling ? 46 : 30, height: isSampling ? 46 : 30)
                .scaleEffect(pulse ? 1.12 : 0.94)

            Circle()
                .fill(isSampling ? Color.accentColor : Color.white)
                .frame(width: 13, height: 13)
                .shadow(color: .white.opacity(0.5), radius: 7)
        }
        .animation(.easeInOut(duration: 0.3), value: isSampling)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
