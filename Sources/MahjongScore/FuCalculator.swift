import Foundation

/// 待ちの形
public enum WaitKind: String, CaseIterable, Sendable {
    case ryanmen = "両面・双碰"
    case kanchan = "嵌張"
    case penchan = "辺張"
    case tanki = "単騎"

    public var fu: Int {
        switch self {
        case .ryanmen: return 0
        case .kanchan, .penchan, .tanki: return 2
        }
    }
}

/// 雀頭の種類
public enum PairKind: String, CaseIterable, Sendable {
    case none = "数牌・オタ風"
    case yakuhai = "役牌（三元牌・自風・場風のどれか）"
    case doubleWind = "ダブル風（自風＋場風）"

    public var fu: Int {
        switch self {
        case .none: return 0
        case .yakuhai: return 2
        case .doubleWind: return 4 // ルールにより2符とする場合もある
        }
    }
}

/// 面子の種類．順子は0符なので対象外
public enum SetKind: String, CaseIterable, Sendable {
    case ponSimple = "明刻（中張牌）"
    case ponTerminal = "明刻（么九・字牌）"
    case ankouSimple = "暗刻（中張牌）"
    case ankouTerminal = "暗刻（么九・字牌）"
    case minkanSimple = "明槓（中張牌）"
    case minkanTerminal = "明槓（么九・字牌）"
    case ankanSimple = "暗槓（中張牌）"
    case ankanTerminal = "暗槓（么九・字牌）"

    public var fu: Int {
        switch self {
        case .ponSimple: return 2
        case .ponTerminal: return 4
        case .ankouSimple: return 4
        case .ankouTerminal: return 8
        case .minkanSimple: return 8
        case .minkanTerminal: return 16
        case .ankanSimple: return 16
        case .ankanTerminal: return 32
        }
    }
}

/// 符計算の入力と結果
public struct FuCalculator: Equatable, Sendable {
    public var isChiitoitsu: Bool = false
    /// 平和ツモ（20符固定）
    public var isPinfuTsumo: Bool = false
    /// 門前かどうか
    public var isClosedHand: Bool = true
    public var winMethod: WinMethod = .ron
    public var wait: WaitKind = .ryanmen
    public var pair: PairKind = .none
    public var sets: [SetKind] = []

    public init() {}

    /// 内訳（項目名, 符）の配列．合計表示用
    public var breakdown: [(label: String, fu: Int)] {
        if isChiitoitsu { return [("七対子（固定）", 25)] }
        if isPinfuTsumo { return [("平和ツモ（固定）", 20)] }
        var items: [(String, Int)] = [("底符", 20)]
        if winMethod == .ron, isClosedHand {
            items.append(("門前ロン加符", 10))
        }
        if winMethod == .tsumo {
            items.append(("ツモ符", 2))
        }
        if pair.fu > 0 {
            items.append(("雀頭（\(pair.rawValue)）", pair.fu))
        }
        if wait.fu > 0 {
            items.append(("待ち（\(wait.rawValue)）", wait.fu))
        }
        for set in sets {
            items.append((set.rawValue, set.fu))
        }
        return items
    }

    /// 10符単位に切り上げた符．七対子は25，平和ツモは20
    public var totalFu: Int {
        if isChiitoitsu { return 25 }
        if isPinfuTsumo { return 20 }
        let raw = breakdown.reduce(0) { $0 + $1.fu }
        // 20符ぴったりは「喰いピンフ形」として30符扱いが一般的
        if raw == 20 { return 30 }
        return ((raw + 9) / 10) * 10
    }
}
