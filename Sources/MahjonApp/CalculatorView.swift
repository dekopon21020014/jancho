import MahjongScore
import SwiftUI

struct CalculatorView: View {
    @State private var han = 1
    @State private var fu = 30
    @State private var isDealer = false
    @State private var winMethod: WinMethod = .ron
    @State private var honba = 0
    @State private var riichiSticks = 0
    @State private var isChiitoitsu = false
    @State private var yakumanCount = 0
    @State private var playerCount = 4

    private var result: ScoreResult {
        ScoreCalculator.calculate(
            ScoreInput(
                han: han,
                fu: fu,
                isDealer: isDealer,
                winMethod: winMethod,
                honba: honba,
                riichiSticks: riichiSticks,
                isChiitoitsu: isChiitoitsu,
                yakumanCount: yakumanCount,
                playerCount: playerCount
            )
        )
    }

    private let chipColumns = [GridItem(.adaptive(minimum: 54), spacing: 8)]

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        resultCard
                        winCard
                        if yakumanCount == 0 {
                            hanFuCard
                        } else {
                            yakumanCard
                        }
                        sticksRow
                    }
                    .padding(16)
                }
            }
            .navigationTitle("点数計算")
        }
    }

    // MARK: - 結果カード

    private var resultCard: some View {
        TileCard {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("🀄")
                        .font(.title2)
                    if !result.rankName.isEmpty {
                        Text(result.rankName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background {
                                Capsule().fill(
                                    LinearGradient(colors: [Theme.gold, Theme.accent],
                                                   startPoint: .leading, endPoint: .trailing))
                            }
                    }
                    Spacer()
                    Text("\(isDealer ? "親" : "子") ・ \(winMethod.rawValue)\(yakumanCount == 0 ? " ・ \(isChiitoitsu ? 25 : fu)符 \(han)翻" : "")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.subInk)
                }
                Text(result.displayText)
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("合計 \(result.totalReceived) 点")
                    .font(.headline)
                    .foregroundStyle(Theme.green)
                paymentTiles
            }
        }
    }

    /// 支払い内訳のミニ牌
    @ViewBuilder
    private var paymentTiles: some View {
        let items: [(String, Int)] = {
            var list: [(String, Int)] = []
            if let ron = result.ronPayment { list.append(("放銃者", ron)) }
            if let dealer = result.tsumoDealerPayment {
                list.append((isDealer ? "全員" : "親", dealer))
            }
            if let child = result.tsumoChildPayment { list.append(("子", child)) }
            if riichiSticks > 0 { list.append(("供託", riichiSticks * 1000)) }
            return list
        }()
        if items.count > 1 || riichiSticks > 0 {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 1) {
                        Text(item.0)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.subInk)
                        Text("\(item.1)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.chipOff)
                    }
                }
            }
        }
    }

    // MARK: - あがりカード

    private var winCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "あがり", systemImage: "person.2")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                ForEach(3...7, id: \.self) { count in
                    Chip(title: "\(count)人", selected: playerCount == count,
                         accent: count == 3 ? Theme.gold : Theme.green) {
                        playerCount = count
                    }
                }
            }
            if playerCount == 3 {
                Text("三人打ちはツモ損あり（不在の1人分は受け取れません）．")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            HStack(spacing: 10) {
                BigToggle(title: "子", subtitle: "通常の点数", selected: !isDealer) {
                    isDealer = false
                }
                BigToggle(title: "親", subtitle: "点数は1.5倍", selected: isDealer, accent: Theme.accent) {
                    isDealer = true
                }
            }
            HStack(spacing: 10) {
                BigToggle(title: "ロン", subtitle: "放銃者から全額", selected: winMethod == .ron, accent: Theme.accent) {
                    winMethod = .ron
                }
                BigToggle(title: "ツモ", subtitle: "全員から徴収", selected: winMethod == .tsumo) {
                    winMethod = .tsumo
                }
            }
        }
    }

    // MARK: - 翻・符カード

    private var hanFuCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "翻と符", systemImage: "square.grid.3x3")
            TileCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("翻数")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.subInk)
                    LazyVGrid(columns: chipColumns, spacing: 8) {
                        ForEach(1...13, id: \.self) { value in
                            Chip(title: "\(value)", selected: han == value) {
                                han = value
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Text("符")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.subInk)
                        Spacer()
                        Chip(title: "七対子 25符", selected: isChiitoitsu, accent: Theme.gold) {
                            isChiitoitsu.toggle()
                        }
                        .frame(width: 130)
                    }
                    if !isChiitoitsu {
                        LazyVGrid(columns: chipColumns, spacing: 8) {
                            ForEach(Array(stride(from: 20, through: 110, by: 10)), id: \.self) { value in
                                Chip(title: "\(value)", selected: fu == value) {
                                    fu = value
                                }
                            }
                        }
                    } else {
                        Text("七対子は25符固定")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subInk)
                    }
                    Divider()
                    yakumanPicker
                }
            }
        }
    }

    private var yakumanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "役満", systemImage: "crown")
            TileCard {
                yakumanPicker
            }
        }
    }

    private var yakumanPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("役満")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.subInk)
            HStack(spacing: 8) {
                Chip(title: "なし", selected: yakumanCount == 0) { yakumanCount = 0 }
                Chip(title: "役満", selected: yakumanCount == 1, accent: Theme.accent) { yakumanCount = 1 }
                Chip(title: "ダブル", selected: yakumanCount == 2, accent: Theme.accent) { yakumanCount = 2 }
                Chip(title: "トリプル", selected: yakumanCount == 3, accent: Theme.accent) { yakumanCount = 3 }
            }
        }
    }

    // MARK: - 積み棒・供託

    private var sticksRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "積み棒・供託", systemImage: "rectangle.stack")
            HStack(spacing: 10) {
                StepperTile(title: "本場", value: $honba, range: 0...20, unit: "本場")
                StepperTile(title: "供託リーチ棒", value: $riichiSticks, range: 0...10, unit: "本")
            }
        }
    }
}
