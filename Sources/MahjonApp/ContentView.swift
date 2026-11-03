import SwiftUI

// MARK: - テーマ（雀卓グリーン＋牌ホワイト）

enum Theme {
    static let feltTop = Color(red: 0.08, green: 0.38, blue: 0.24)
    static let feltBottom = Color(red: 0.02, green: 0.19, blue: 0.12)
    static let tile = Color.white
    static let ink = Color(red: 0.13, green: 0.14, blue: 0.13)
    static let subInk = Color(red: 0.42, green: 0.45, blue: 0.42)
    static let accent = Color(red: 0.85, green: 0.24, blue: 0.20) // 赤（ドラ色）
    static let gold = Color(red: 0.83, green: 0.62, blue: 0.13)
    static let green = Color(red: 0.09, green: 0.46, blue: 0.28)
    static let chipOff = Color(red: 0.93, green: 0.94, blue: 0.92)

    static let fuPalette: [Color] = [
        Color(red: 0.09, green: 0.46, blue: 0.28),
        Color(red: 0.85, green: 0.24, blue: 0.20),
        Color(red: 0.83, green: 0.62, blue: 0.13),
        Color(red: 0.16, green: 0.45, blue: 0.72),
        Color(red: 0.52, green: 0.35, blue: 0.75),
        Color(red: 0.90, green: 0.50, blue: 0.15),
        Color(red: 0.20, green: 0.65, blue: 0.62),
        Color(red: 0.55, green: 0.55, blue: 0.55),
    ]
}

/// 雀卓のフェルト背景
struct FeltBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.feltTop, Theme.feltBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// 牌みたいな白カード．下端に牌の厚みっぽい影をつける
struct TileCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.tile)
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 4)
            }
            // カード内は常に白背景前提の配色．端末がダークモードでも
            // TextField等の標準部品が白文字にならないようライト固定にする
            .environment(\.colorScheme, .light)
    }
}

/// カードの見出し（フェルト上の白文字ラベル）
struct FeltLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
    }
}

/// 選択チップ
struct Chip: View {
    let title: String
    let selected: Bool
    var accent: Color = Theme.green
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .foregroundStyle(selected ? .white : Theme.ink)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? accent : Theme.chipOff)
                        .shadow(color: .black.opacity(selected ? 0.25 : 0.08),
                                radius: selected ? 3 : 1, x: 0, y: 2)
                }
        }
        .buttonStyle(.plain)
    }
}

/// 大きな2択トグル牌
struct BigToggle: View {
    let title: String
    let subtitle: String
    let selected: Bool
    var accent: Color = Theme.green
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.75)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? .white : Theme.ink)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? accent : Theme.tile)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 3)
            }
        }
        .buttonStyle(.plain)
    }
}

/// − ＋ ステッパー牌
struct StepperTile: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.subInk)
            HStack(spacing: 10) {
                stepButton(systemName: "minus", enabled: value > range.lowerBound) {
                    value = max(range.lowerBound, value - 1)
                }
                Text("\(value)\(unit)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .frame(minWidth: 64)
                stepButton(systemName: "plus", enabled: value < range.upperBound) {
                    value = min(range.upperBound, value + 1)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.tile)
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 3)
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 34, height: 34)
                .foregroundStyle(.white)
                .background(Circle().fill(enabled ? Theme.green : Color.gray.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - ルート

struct ContentView: View {
    var body: some View {
        TabView {
            LiveGameView()
                .tabItem { Label("対局", systemImage: "person.3.fill") }
            CalculatorView()
                .tabItem { Label("点数計算", systemImage: "textformat.123") }
            FuCalculatorView()
                .tabItem { Label("符計算", systemImage: "plus.circle") }
            ScoreTableView()
                .tabItem { Label("早見表", systemImage: "tablecells") }
            RecordsView()
                .tabItem { Label("成績", systemImage: "chart.bar") }
        }
        .tint(Theme.green)
    }
}
