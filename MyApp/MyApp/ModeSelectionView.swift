import SwiftUI
import SwiftData

struct ModeSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = GameViewModel()
    @State private var showingSolo = false
    @State private var showingFriends = false

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "suit.spade.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.masterGold)
                    Text("The Shady Spade")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("Choose a game mode")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 52)

                VStack(spacing: 16) {
                    ModeCard(
                        icon: "person.fill.badge.plus",
                        title: "Play Solo",
                        subtitle: "Face 5 AI opponents in a fully simulated game",
                        color: .masterGold
                    ) {
                        HapticManager.impact(.medium)
                        showingSolo = true
                    }

                    ModeCard(
                        icon: "person.3.fill",
                        title: "Play with Friends",
                        subtitle: "6-player manual score tracker",
                        color: .offenseBlue
                    ) {
                        HapticManager.impact(.medium)
                        showingFriends = true
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .onAppear { vm.setup(with: modelContext) }
        .fullScreenCover(isPresented: $showingSolo) {
            ComputerGameView(vm: vm)
        }
        .fullScreenCover(isPresented: $showingFriends) {
            MainView()
                .environment(authVM)
        }
    }
}

private struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(color.opacity(0.6))
            }
            .padding(20)
            .glassmorphic(cornerRadius: 20)
        }
        .buttonStyle(BouncyButton())
    }
}
