import MahjongScore
import SwiftUI

struct FuCalculatorView: View {
    @State private var calculator = FuCalculator()
    @State private var selectedSet: SetKind = .ponSimple

    private var rawTotal: Int {
        calculator.breakdown.reduce(0) { $0 + $1.fu }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        resultCard
                        shapeCard
                        if !calculator.isChiitoitsu && !calculator.isPinfuTsumo {
                            setsCard
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("符計算")
        }
    }

    // MARK: - 結果（内訳バー付き）

    private var resultCard: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(calculator.totalFu)")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("符")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if !calculator.isChiitoitsu && !calculator.isPinfuTsumo {
                        Text("合計 \(rawTotal)符 → 切り上げ")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subInk)
                    }
                }
                breakdownBar
                VStack(spacing: 7) {
                    ForEach(Array(calculator.breakdown.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Theme.fuPalette[index % Theme.fuPalette.count])
                                .frame(width: 10, height: 10)
                            Text(item.label)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(item.fu)符")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background {
                                    Capsule().fill(Theme.fuPalette[index % Theme.fuPalette.count])
                                }
                        }
                    }
                }
            }
        }
    }

    /// 内訳の割合を積み上げバーで表示
    private var breakdownBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(calculator.breakdown.enumerated()), id: \.offset) { index, item in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.fuPalette[index % Theme.fuPalette.count])
                        .frame(width: max(geo.size.width * CGFloat(item.fu) / CGFloat(max(rawTotal, 1)) - 2, 3))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 16)
    }

    // MARK: - 形カード

    private var shapeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "形", systemImage: "square.grid.2x2")
            TileCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("七対子（25符固定）", isOn: $calculator.isChiitoitsu)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Toggle("平和ツモ（20符固定）", isOn: $calculator.isPinfuTsumo)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if !calculator.isChiitoitsu && !calculator.isPinfuTsumo {
                        Divider()
                        Toggle("門前", isOn: $calculator.isClosedHand)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        HStack(spacing: 8) {
                            Chip(title: "ロン", selected: calculator.winMethod == .ron, accent: Theme.accent) {
                                calculator.winMethod = .ron
                            }
                            Chip(title: "ツモ", selected: calculator.winMethod == .tsumo) {
                                calculator.winMethod = .tsumo
                            }
                        }
                        Text("雀頭")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.subInk)
                        VStack(spacing: 8) {
                            ForEach(PairKind.allCases, id: \.self) { pair in
                                Chip(title: pair.rawValue, selected: calculator.pair == pair) {
                                    calculator.pair = pair
                                }
                            }
                        }
                        Text("待ち")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.subInk)
                        HStack(spacing: 8) {
                            ForEach(WaitKind.allCases, id: \.self) { wait in
                                Chip(title: wait.rawValue.components(separatedBy: "・").first ?? wait.rawValue,
                                     selected: calculator.wait == wait) {
                                    calculator.wait = wait
                                }
                            }
                        }
                        Text("両面・双碰は0符，嵌張・辺張・単騎は2符")
                            .font(.caption)
                            .foregroundStyle(Theme.subInk)
                    }
                }
            }
        }
    }

    // MARK: - 面子カード

    private var setsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "刻子・槓子（順子は0符）", systemImage: "square.stack.3d.up")
            TileCard {
                VStack(alignment: .leading, spacing: 12) {
                    if calculator.sets.isEmpty {
                        Text("まだ面子がありません．下のチップで追加（最大4つ）")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subInk)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(calculator.sets.enumerated()), id: \.offset) { index, set in
                                HStack {
                                    Text(set.rawValue)
                                        .font(.headline)
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text("\(set.fu)符")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(Theme.green)
                                    Button {
                                        calculator.sets.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Theme.chipOff)
                                }
                            }
                        }
                    }
                    Divider()
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(SetKind.allCases, id: \.self) { set in
                            Chip(title: "\(set.rawValue) \(set.fu)", selected: false) {
                                if calculator.sets.count < 4 {
                                    calculator.sets.append(set)
                                }
                            }
                        }
                    }
                    if calculator.sets.count >= 4 {
                        Text("面子は4つまで")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }
}
