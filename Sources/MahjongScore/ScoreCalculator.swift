import Foundation

/// あがり方
public enum WinMethod: String, CaseIterable, Sendable {
    case ron = "ロン"
    case tsumo = "ツモ"
}

/// 点数計算の入力
public struct ScoreInput: Equatable, Sendable {
    /// 翻数．1〜13．13以上は `yakumanCount` で数えること
    public var han: Int
    /// 符．20〜110を10符単位．七対子は25
    public var fu: Int
    /// 親かどうか
    public var isDealer: Bool
    public var winMethod: WinMethod
    /// 本場数．ロン+300/本場，ツモ+100/本場/人
    public var honba: Int
    /// 供託リーチ棒の本数．1本=1,000点を勝者が受け取る
    public var riichiSticks: Int
    /// 七対子かどうか．trueなら符は25で固定される
    public var isChiitoitsu: Bool
    /// 役満の倍数．0なら通常計算，1=役満，2=ダブル役満…
    public var yakumanCount: Int
    /// 人数．3=三人打ち（ツモは不在分を徴収しない＝ツモ損あり），
    /// 4以上はツモ全員払い（多人数打ち対応）
    public var playerCount: Int

    public init(
        han: Int = 1,
        fu: Int = 30,
        isDealer: Bool = false,
        winMethod: WinMethod = .ron,
        honba: Int = 0,
        riichiSticks: Int = 0,
        isChiitoitsu: Bool = false,
        yakumanCount: Int = 0,
        playerCount: Int = 4
    ) {
        self.han = han
        self.fu = fu
        self.isDealer = isDealer
        self.winMethod = winMethod
        self.honba = honba
        self.riichiSticks = riichiSticks
        self.isChiitoitsu = isChiitoitsu
        self.yakumanCount = yakumanCount
        self.playerCount = min(7, max(3, playerCount))
    }
}

/// 点数計算の結果
public struct ScoreResult: Equatable, Sendable {
    /// 基本点（切り上げ前）
    public let basePoints: Int
    /// 満貫・跳満などの区分名．該当なしは ""
    public let rankName: String
    /// 放銃者が払う点数（ロンのみ，本場込み）
    public let ronPayment: Int?
    /// ツモ時に親が払う点数（本場込み）．親ツモでは全員分がこの値
    public let tsumoDealerPayment: Int?
    /// ツモ時に子が払う点数（本場込み）．親ツモでは nil
    public let tsumoChildPayment: Int?
    /// 勝者が受け取る合計（本場・供託込み）
    public let totalReceived: Int
    /// 表示用の一文．例: "8000", "2000オール", "1000 / 2000"（子ツモ，子/親）
    public let displayText: String
}

public enum ScoreCalculator {
    /// 100点単位への切り上げ
    public static func ceil100(_ value: Int) -> Int {
        ((value + 99) / 100) * 100
    }

    /// 基本点と区分名を返す
    public static func basePoints(han: Int, fu: Int, yakumanCount: Int) -> (base: Int, rank: String) {
        if yakumanCount > 0 {
            let rank = yakumanCount == 1 ? "役満" : "\(yakumanCount)倍役満"
            return (8000 * yakumanCount, rank)
        }
        switch han {
        case 13...:
            return (8000, "数え役満")
        case 11...12:
            return (6000, "三倍満")
        case 8...10:
            return (4000, "倍満")
        case 6...7:
            return (3000, "跳満")
        case 5:
            return (2000, "満貫")
        default:
            // 基本点 = 符 × 2^(翻+2)
            let raw = fu * (1 << (han + 2))
            if raw >= 2000 {
                return (2000, "満貫")
            }
            return (raw, "")
        }
    }

    public static func calculate(_ input: ScoreInput) -> ScoreResult {
        let fu = input.isChiitoitsu ? 25 : input.fu
        let (base, rank) = basePoints(han: input.han, fu: fu, yakumanCount: input.yakumanCount)
        let honba = max(0, input.honba)
        let kyotaku = max(0, input.riichiSticks) * 1000

        switch input.winMethod {
        case .ron:
            let multiplier = input.isDealer ? 6 : 4
            let payment = ceil100(base * multiplier) + honba * 300
            return ScoreResult(
                basePoints: base,
                rankName: rank,
                ronPayment: payment,
                tsumoDealerPayment: nil,
                tsumoChildPayment: nil,
                totalReceived: payment + kyotaku,
                displayText: "\(payment)"
            )
        case .tsumo:
            // 支払う相手の数．三人打ちは不在分を徴収しない（ツモ損），
            // 5人以上の多人数打ちは全員払い
            let opponents = input.playerCount - 1
            if input.isDealer {
                let each = ceil100(base * 2) + honba * 100
                return ScoreResult(
                    basePoints: base,
                    rankName: rank,
                    ronPayment: nil,
                    tsumoDealerPayment: each,
                    tsumoChildPayment: nil,
                    totalReceived: each * opponents + kyotaku,
                    displayText: "\(each)オール"
                )
            } else {
                let fromDealer = ceil100(base * 2) + honba * 100
                let fromChild = ceil100(base * 1) + honba * 100
                return ScoreResult(
                    basePoints: base,
                    rankName: rank,
                    ronPayment: nil,
                    tsumoDealerPayment: fromDealer,
                    tsumoChildPayment: fromChild,
                    totalReceived: fromDealer + fromChild * (opponents - 1) + kyotaku,
                    // 表記は慣例の「子の支払い / 親の支払い」
                    displayText: "\(fromChild) / \(fromDealer)"
                )
            }
        }
    }
}
