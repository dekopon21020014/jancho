import MahjongScore
import SwiftUI

/// 早見表の1行分
private struct Row: Identifiable {
    var id: String { "\(han)-\(fu)" }
    let han: Int
    let fu: Int
    let childRon: String
    let childTsumo: String
    let dealerRon: String
    let dealerTsumo: String
    /// 子ロンが満貫以上かどうか（強調表示用）
    let isMangan: Bool
}

private func makeRows() -> [Row] {
    var rows: [Row] = []
    for han in 1...4 {
        for fu in [25, 30, 40, 50, 60, 70, 80, 90, 100, 110] {
            // 25符は七対子（2翻〜）のみ．20符（平和ツモ）は計算タブで扱う
            if fu == 25 && han == 1 { continue }
            let childRon = ScoreCalculator.calculate(
                ScoreInput(han: han, fu: fu, winMethod: .ron))
            let childTsumo = ScoreCalculator.calculate(
                ScoreInput(han: han, fu: fu, winMethod: .tsumo))
            let dealerRon = ScoreCalculator.calculate(
                ScoreInput(han: han, fu: fu, isDealer: true, winMethod: .ron))
            let dealerTsumo = ScoreCalculator.calculate(
                ScoreInput(han: han, fu: fu, isDealer: true, winMethod: .tsumo))
            rows.append(Row(
                han: han, fu: fu,
                childRon: childRon.displayText,
                childTsumo: childTsumo.displayText,
                dealerRon: dealerRon.displayText,
                dealerTsumo: dealerTsumo.displayText,
                isMangan: !childRon.rankName.isEmpty
            ))
        }
    }
    return rows
}

struct ScoreTableView: View {
    private let rows = makeRows()

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(1...4, id: \.self) { han in
                            VStack(alignment: .leading, spacing: 10) {
                                FeltLabel(title: "\(han)翻", systemImage: "list.number")
                                ForEach(rows.filter { $0.han == han }) { row in
                                    rowCard(row)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("早見表（1〜4翻）")
        }
    }

    private func rowCard(_ row: Row) -> some View {
        TileCard {
            HStack(spacing: 12) {
                // 符の牌
                VStack(spacing: 0) {
                    Text("\(row.fu)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("符")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(row.isMangan
                              ? LinearGradient(colors: [Theme.gold, Theme.accent],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Theme.green, Theme.green],
                                               startPoint: .top, endPoint: .bottom))
                }
                // 2×2スコアグリッド
                Grid(horizontalSpacing: 10, verticalSpacing: 5) {
                    GridRow {
                        scoreCell(label: "子 ロン", value: row.childRon, highlight: row.isMangan)
                        scoreCell(label: "子 ツモ", value: row.childTsumo, highlight: false)
                    }
                    GridRow {
                        scoreCell(label: "親 ロン", value: row.dealerRon, highlight: row.isMangan)
                        scoreCell(label: "親 ツモ", value: row.dealerTsumo, highlight: false)
                    }
                }
            }
        }
    }

    private func scoreCell(label: String, value: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.subInk)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ? Theme.accent : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
