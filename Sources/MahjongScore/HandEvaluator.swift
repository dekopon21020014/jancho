import Foundation

// MARK: - 牌

/// 牌種．index 0...33: 0-8=萬子1-9, 9-17=筒子1-9, 18-26=索子1-9, 27-33=東南西北白發中
public enum TileKind {
    public static func suit(of tile: Int) -> Int { tile / 9 } // 0=萬 1=筒 2=索 3=字
    public static func rank(of tile: Int) -> Int { suit(of: tile) == 3 ? tile - 27 : tile % 9 + 1 }
    public static func isHonor(_ tile: Int) -> Bool { suit(of: tile) == 3 }
    public static func isTerminal(_ tile: Int) -> Bool {
        suit(of: tile) != 3 && (rank(of: tile) == 1 || rank(of: tile) == 9)
    }
    public static func isTerminalOrHonor(_ tile: Int) -> Bool { isTerminal(tile) || isHonor(tile) }
    public static func isSimple(_ tile: Int) -> Bool { !isTerminalOrHonor(tile) }
    public static func isDragon(_ tile: Int) -> Bool { tile >= 31 }
    public static func isWind(_ tile: Int) -> Bool { tile >= 27 && tile <= 30 }

    /// ドラ表示牌から，ドラになる牌を返す．
    /// 数牌は次の数（9の次は1），風牌は東南西北の順，三元牌は白發中の順に循環する
    public static func doraTile(fromIndicator tile: Int) -> Int {
        if tile < 27 {
            let base = tile / 9 * 9
            return base + (tile - base + 1) % 9
        }
        if tile < 31 { return 27 + (tile - 27 + 1) % 4 }
        return 31 + (tile - 31 + 1) % 3
    }

    public static func name(of tile: Int) -> String {
        let numerals = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
        switch suit(of: tile) {
        case 0: return numerals[rank(of: tile) - 1] + "萬"
        case 1: return numerals[rank(of: tile) - 1] + "筒"
        case 2: return numerals[rank(of: tile) - 1] + "索"
        default: return ["東", "南", "西", "北", "白", "發", "中"][tile - 27]
        }
    }
}

/// 副露面子
public struct Meld: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case shuntsu, pon, minkan, ankan
    }
    public var kind: Kind
    /// 順子は最小牌，刻子・槓子はその牌
    public var tile: Int

    public init(kind: Kind, tile: Int) {
        self.kind = kind
        self.tile = tile
    }

    public var isOpen: Bool { kind != .ankan }

    /// 面子を構成する牌（槓子は4枚）
    public var tiles: [Int] {
        switch kind {
        case .shuntsu: return [tile, tile + 1, tile + 2]
        case .pon: return [tile, tile, tile]
        case .minkan, .ankan: return [tile, tile, tile, tile]
        }
    }
}

/// あがり状況
public struct HandContext: Sendable {
    public var isTsumo: Bool = false
    public var isRiichi: Bool = false
    public var isDoubleRiichi: Bool = false
    public var isIppatsu: Bool = false
    /// 海底ツモ・河底ロン
    public var isHaitei: Bool = false
    public var isRinshan: Bool = false
    public var isChankan: Bool = false
    /// 0=東 1=南 2=西 3=北
    public var seatWind: Int = 0
    /// 0=東場 1=南場
    public var roundWind: Int = 0
    /// 赤ドラ以外のドラ枚数（赤は HandInput.redFives で数える）
    public var doraCount: Int = 0

    public init() {}
}

public struct HandInput: Sendable {
    /// あがり牌を含む手牌（副露分を除く）
    public var closedTiles: [Int] = []
    /// 赤5の枚数（手牌＋副露の合計）
    public var redFives: Int = 0
    public var melds: [Meld] = []
    public var winningTile: Int = 0
    public var context = HandContext()

    public init() {}
}

public struct EvaluatedYaku: Equatable, Sendable {
    public var name: String
    public var han: Int
    public init(name: String, han: Int) {
        self.name = name
        self.han = han
    }
}

public struct HandEvaluation: Equatable, Sendable {
    /// ドラ込みの合計翻．役満のときは0
    public var han: Int
    public var fu: Int
    public var yakumanCount: Int
    public var isChiitoitsu: Bool
    public var yaku: [EvaluatedYaku]
    /// ドラとして加算した枚数
    public var dora: Int
}

// MARK: - 判定エンジン

public enum HandEvaluator {
    public static func evaluate(_ input: HandInput) -> HandEvaluation? {
        // 枚数チェック: 手牌 + 副露×3 = 14
        guard input.closedTiles.count + input.melds.count * 3 == 14 else { return nil }
        var closedCounts = [Int](repeating: 0, count: 34)
        for tile in input.closedTiles {
            guard (0...33).contains(tile) else { return nil }
            closedCounts[tile] += 1
        }
        var totalCounts = closedCounts
        for meld in input.melds {
            for tile in meld.tiles { totalCounts[tile] += 1 }
        }
        guard totalCounts.allSatisfy({ $0 <= 4 }) else { return nil }
        guard input.closedTiles.contains(input.winningTile) else { return nil }

        let isClosedHand = input.melds.allSatisfy { !$0.isOpen }
        var best: HandEvaluation?

        func consider(_ candidate: HandEvaluation?) {
            guard let candidate else { return }
            if let current = best {
                if scoreKey(candidate) <= scoreKey(current) { return }
            }
            best = candidate
        }

        // 特殊形
        if input.melds.isEmpty {
            consider(evaluateChiitoitsu(input, counts: closedCounts))
            consider(evaluateKokushi(input, counts: closedCounts))
            consider(evaluateChuuren(input, counts: closedCounts))
        }

        // 通常形: 雀頭候補ごとに面子分解（手牌分のみ）
        for pair in 0...33 where closedCounts[pair] >= 2 {
            var rest = closedCounts
            rest[pair] -= 2
            var decompositions: [[RawSet]] = []
            var current: [RawSet] = []
            decompose(&rest, current: &current, results: &decompositions)
            for sets in decompositions {
                evaluateStandard(
                    input: input, pair: pair, rawSets: sets,
                    isClosedHand: isClosedHand, consider: consider)
            }
        }
        return best
    }

    /// 比較用キー（基本点ベース）．大きい方が良い
    private static func scoreKey(_ evaluation: HandEvaluation) -> Int {
        if evaluation.yakumanCount > 0 { return 1_000_000 * evaluation.yakumanCount }
        let (base, _) = ScoreCalculator.basePoints(
            han: evaluation.han, fu: evaluation.fu, yakumanCount: 0)
        return base * 100 + evaluation.han
    }

    // MARK: 面子分解

    private struct RawSet {
        var isShuntsu: Bool
        var tile: Int
    }

    private static func decompose(_ counts: inout [Int], current: inout [RawSet], results: inout [[RawSet]]) {
        guard let first = counts.firstIndex(where: { $0 > 0 }) else {
            results.append(current)
            return
        }
        // 刻子
        if counts[first] >= 3 {
            counts[first] -= 3
            current.append(RawSet(isShuntsu: false, tile: first))
            decompose(&counts, current: &current, results: &results)
            current.removeLast()
            counts[first] += 3
        }
        // 順子
        let suit = TileKind.suit(of: first)
        let rank = TileKind.rank(of: first)
        if suit < 3, rank <= 7, counts[first + 1] > 0, counts[first + 2] > 0 {
            counts[first] -= 1
            counts[first + 1] -= 1
            counts[first + 2] -= 1
            current.append(RawSet(isShuntsu: true, tile: first))
            decompose(&counts, current: &current, results: &results)
            current.removeLast()
            counts[first] += 1
            counts[first + 1] += 1
            counts[first + 2] += 1
        }
    }

    private struct SetInfo {
        var isShuntsu: Bool
        var tile: Int
        /// 暗刻・暗槓，またはロンで完成していない刻子かどうか（符・三暗刻用）
        var isClosed: Bool
        var isKan: Bool
    }

    // MARK: 通常形の評価

    private static func evaluateStandard(
        input: HandInput, pair: Int, rawSets: [RawSet],
        isClosedHand: Bool, consider: (HandEvaluation?) -> Void
    ) {
        let context = input.context
        let win = input.winningTile

        // 副露を SetInfo に変換
        var meldSets: [SetInfo] = input.melds.map { meld in
            switch meld.kind {
            case .shuntsu: return SetInfo(isShuntsu: true, tile: meld.tile, isClosed: false, isKan: false)
            case .pon: return SetInfo(isShuntsu: false, tile: meld.tile, isClosed: false, isKan: false)
            case .minkan: return SetInfo(isShuntsu: false, tile: meld.tile, isClosed: false, isKan: true)
            case .ankan: return SetInfo(isShuntsu: false, tile: meld.tile, isClosed: true, isKan: true)
            }
        }

        // 待ちの解釈候補: (待ち種別, あがり牌で完成した刻子のindex or -1)
        var waitOptions: [(wait: WaitKind, winningPonIndex: Int)] = []
        if pair == win {
            waitOptions.append((.tanki, -1))
        }
        for (index, set) in rawSets.enumerated() {
            if set.isShuntsu {
                if win == set.tile {
                    waitOptions.append((TileKind.rank(of: set.tile) == 7 ? .penchan : .ryanmen, -1))
                } else if win == set.tile + 1 {
                    waitOptions.append((.kanchan, -1))
                } else if win == set.tile + 2 {
                    waitOptions.append((TileKind.rank(of: set.tile) == 1 ? .penchan : .ryanmen, -1))
                }
            } else if set.tile == win {
                waitOptions.append((.ryanmen, index)) // 双碰扱い（0符）
            }
        }
        if waitOptions.isEmpty { return }

        var seenWaits = Set<String>()
        for option in waitOptions {
            let key = "\(option.wait.rawValue)-\(option.winningPonIndex >= 0)"
            if seenWaits.contains(key) { continue }
            seenWaits.insert(key)

            var sets: [SetInfo] = meldSets
            for (index, set) in rawSets.enumerated() {
                if set.isShuntsu {
                    sets.append(SetInfo(isShuntsu: true, tile: set.tile, isClosed: true, isKan: false))
                } else {
                    // ロンで完成した刻子は明刻扱い
                    let closed = !(!context.isTsumo && index == option.winningPonIndex)
                    sets.append(SetInfo(isShuntsu: false, tile: set.tile, isClosed: closed, isKan: false))
                }
            }

            consider(evaluateSets(
                input: input, pair: pair, sets: sets, wait: option.wait,
                isClosedHand: isClosedHand))
        }
    }

    // MARK: 役判定（通常形）

    private static func evaluateSets(
        input: HandInput, pair: Int, sets: [SetInfo], wait: WaitKind, isClosedHand: Bool
    ) -> HandEvaluation? {
        let context = input.context
        let allTiles: [Int] = sets.flatMap { set -> [Int] in
            set.isShuntsu ? [set.tile, set.tile + 1, set.tile + 2] : [set.tile, set.tile, set.tile]
        } + [pair, pair]
        var yaku: [EvaluatedYaku] = []
        var yakuman = 0

        func add(_ name: String, _ han: Int) { yaku.append(EvaluatedYaku(name: name, han: han)) }

        let pons = sets.filter { !$0.isShuntsu }
        let shuntsus = sets.filter { $0.isShuntsu }
        let closedPons = pons.filter { $0.isClosed }
        let kans = sets.filter { $0.isKan }
        let allSimple = allTiles.allSatisfy { TileKind.isSimple($0) }
        let hasHonorTile = allTiles.contains { TileKind.isHonor($0) }
        // チャンタ系: 全ての面子と雀頭が么九・字牌を含む形か（順子は1・9を含むもの）
        let chantaiShape = sets.allSatisfy { set in
            set.isShuntsu
                ? (TileKind.rank(of: set.tile) == 1 || TileKind.rank(of: set.tile) == 7)
                : TileKind.isTerminalOrHonor(set.tile)
        } && TileKind.isTerminalOrHonor(pair)

        // --- 役満 ---
        // 四暗刻
        if closedPons.count == 4 {
            if wait == .tanki {
                yakuman += 2
                add("四暗刻単騎", 0)
            } else {
                yakuman += 1
                add("四暗刻", 0)
            }
        }
        // 大三元
        let dragonPons = pons.filter { TileKind.isDragon($0.tile) }
        if dragonPons.count == 3 {
            yakuman += 1
            add("大三元", 0)
        }
        // 字一色
        if allTiles.allSatisfy({ TileKind.isHonor($0) }) {
            yakuman += 1
            add("字一色", 0)
        }
        // 緑一色
        let greenTiles: Set<Int> = [19, 20, 21, 23, 25, 32] // 索2,3,4,6,8, 發
        if allTiles.allSatisfy({ greenTiles.contains($0) }) {
            yakuman += 1
            add("緑一色", 0)
        }
        // 清老頭（順子は1・9を含むもののみ，全て数牌の么九）
        let chinroutouShape = sets.allSatisfy { set in
            set.isShuntsu
                ? (TileKind.rank(of: set.tile) == 1 || TileKind.rank(of: set.tile) == 7)
                : TileKind.isTerminal(set.tile)
        } && TileKind.isTerminal(pair)
        if chinroutouShape, !hasHonorTile {
            yakuman += 1
            add("清老頭", 0)
        }
        // 四槓子
        if kans.count == 4 {
            yakuman += 1
            add("四槓子", 0)
        }
        // 小四喜・大四喜
        let windPons = pons.filter { TileKind.isWind($0.tile) }
        if windPons.count == 4 {
            yakuman += 2
            add("大四喜", 0)
        } else if windPons.count == 3, TileKind.isWind(pair) {
            yakuman += 1
            add("小四喜", 0)
        }
        if yakuman > 0 {
            return HandEvaluation(
                han: 0, fu: 40, yakumanCount: yakuman, isChiitoitsu: false,
                yaku: yaku.filter { $0.han == 0 }, dora: 0)
        }

        // --- 状況役 ---
        if context.isDoubleRiichi {
            add("ダブルリーチ", 2)
        } else if context.isRiichi {
            add("リーチ", 1)
        }
        if context.isIppatsu, context.isRiichi || context.isDoubleRiichi {
            add("一発", 1)
        }
        if context.isTsumo, isClosedHand {
            add("門前清自摸和", 1)
        }
        if context.isHaitei {
            add(context.isTsumo ? "海底摸月" : "河底撈魚", 1)
        }
        if context.isRinshan, context.isTsumo {
            add("嶺上開花", 1)
        }
        if context.isChankan, !context.isTsumo {
            add("槍槓", 1)
        }

        // --- 手役 ---
        // 平和: 門前・全順子・役牌でない雀頭・両面待ち
        let pairIsYakuhai = TileKind.isDragon(pair)
            || pair == 27 + context.seatWind
            || pair == 27 + context.roundWind
        let isPinfuShape = shuntsus.count == 4 && !pairIsYakuhai && wait == .ryanmen
        if isPinfuShape, isClosedHand {
            add("平和", 1)
        }
        // 断ヤオ九
        if allSimple {
            add("断ヤオ九", 1)
        }
        // 一盃口・二盃口（門前のみ）
        if isClosedHand {
            var shuntsuCounts: [Int: Int] = [:]
            for set in shuntsus { shuntsuCounts[set.tile, default: 0] += 1 }
            let pairs = shuntsuCounts.values.reduce(0) { $0 + $1 / 2 }
            if pairs == 2 {
                add("二盃口", 3)
            } else if pairs == 1 {
                add("一盃口", 1)
            }
        }
        // 役牌
        for pon in pons {
            if TileKind.isDragon(pon.tile) {
                add("役牌 " + TileKind.name(of: pon.tile), 1)
            } else if TileKind.isWind(pon.tile) {
                if pon.tile == 27 + context.roundWind { add("役牌 場風", 1) }
                if pon.tile == 27 + context.seatWind { add("役牌 自風", 1) }
            }
        }
        // 小三元
        if dragonPons.count == 2, TileKind.isDragon(pair) {
            add("小三元", 2)
        }
        // 三色同刻
        var ponRanks: [Int: Set<Int>] = [:]
        for pon in pons where !TileKind.isHonor(pon.tile) {
            ponRanks[TileKind.rank(of: pon.tile), default: []].insert(TileKind.suit(of: pon.tile))
        }
        if ponRanks.values.contains(where: { $0.count == 3 }) {
            add("三色同刻", 2)
        }
        // 三色同順
        var shuntsuByRank: [Int: Set<Int>] = [:]
        for set in shuntsus {
            shuntsuByRank[TileKind.rank(of: set.tile), default: []].insert(TileKind.suit(of: set.tile))
        }
        if shuntsuByRank.values.contains(where: { $0.count == 3 }) {
            add("三色同順", isClosedHand ? 2 : 1)
        }
        // 一気通貫
        var shuntsuBases: [Int: Set<Int>] = [:] // suit -> base ranks
        for set in shuntsus {
            shuntsuBases[TileKind.suit(of: set.tile), default: []].insert(TileKind.rank(of: set.tile))
        }
        if shuntsuBases.values.contains(where: { $0.isSuperset(of: [1, 4, 7]) }) {
            add("一気通貫", isClosedHand ? 2 : 1)
        }
        // チャンタ・混老頭・純チャン
        let hasShuntsu = !shuntsus.isEmpty
        if chantaiShape, hasShuntsu {
            if hasHonorTile {
                add("混全帯ヤオ九", isClosedHand ? 2 : 1)
            } else {
                add("純全帯ヤオ九", isClosedHand ? 3 : 2)
            }
        }
        if chantaiShape, !hasShuntsu {
            add("混老頭", 2)
        }
        // 対々和
        if pons.count == 4 {
            add("対々和", 2)
        }
        // 三暗刻
        if closedPons.count == 3 {
            add("三暗刻", 2)
        }
        // 三槓子
        if kans.count == 3 {
            add("三槓子", 2)
        }
        // 混一色・清一色
        let suitsPresent = Set(allTiles.map { TileKind.suit(of: $0) })
        if suitsPresent.count <= 2 {
            let numberSuits = suitsPresent.filter { $0 < 3 }
            if numberSuits.count == 1 {
                if suitsPresent.contains(3) {
                    add("混一色", isClosedHand ? 3 : 2)
                } else {
                    add("清一色", isClosedHand ? 6 : 5)
                }
            }
        }

        let yakuHan = yaku.reduce(0) { $0 + $1.han }
        guard yakuHan > 0 else { return nil }

        // --- 符 ---
        var fuCalc = FuCalculator()
        fuCalc.isClosedHand = isClosedHand
        fuCalc.winMethod = context.isTsumo ? .tsumo : .ron
        fuCalc.wait = wait
        fuCalc.pair = pairKind(pair: pair, context: context)
        fuCalc.isPinfuTsumo = isPinfuShape && isClosedHand && context.isTsumo
        fuCalc.sets = pons.map { setKind(of: $0) }
        let fu = fuCalc.totalFu

        let dora = context.doraCount + input.redFives
        if dora > 0 {
            yaku.append(EvaluatedYaku(name: "ドラ", han: dora))
        }
        return HandEvaluation(
            han: yakuHan + dora, fu: fu, yakumanCount: 0, isChiitoitsu: false,
            yaku: yaku, dora: dora)
    }

    private static func pairKind(pair: Int, context: HandContext) -> PairKind {
        if TileKind.isDragon(pair) { return .yakuhai }
        let isSeat = pair == 27 + context.seatWind
        let isRound = pair == 27 + context.roundWind
        if isSeat && isRound { return .doubleWind }
        if isSeat || isRound { return .yakuhai }
        return .none
    }

    private static func setKind(of set: SetInfo) -> SetKind {
        let terminal = TileKind.isTerminalOrHonor(set.tile)
        switch (set.isKan, set.isClosed) {
        case (true, true): return terminal ? .ankanTerminal : .ankanSimple
        case (true, false): return terminal ? .minkanTerminal : .minkanSimple
        case (false, true): return terminal ? .ankouTerminal : .ankouSimple
        case (false, false): return terminal ? .ponTerminal : .ponSimple
        }
    }

    // MARK: 七対子

    private static func evaluateChiitoitsu(_ input: HandInput, counts: [Int]) -> HandEvaluation? {
        let pairs = counts.filter { $0 == 2 }.count
        guard pairs == 7 else { return nil }
        let context = input.context
        var yaku: [EvaluatedYaku] = []
        var yakuman = 0
        let allTiles = input.closedTiles
        if allTiles.allSatisfy({ TileKind.isHonor($0) }) {
            yakuman = 1
            yaku.append(EvaluatedYaku(name: "字一色", han: 0))
            return HandEvaluation(han: 0, fu: 25, yakumanCount: yakuman,
                                  isChiitoitsu: true, yaku: yaku, dora: 0)
        }
        func add(_ name: String, _ han: Int) { yaku.append(EvaluatedYaku(name: name, han: han)) }
        if context.isDoubleRiichi {
            add("ダブルリーチ", 2)
        } else if context.isRiichi {
            add("リーチ", 1)
        }
        if context.isIppatsu, context.isRiichi || context.isDoubleRiichi { add("一発", 1) }
        if context.isTsumo { add("門前清自摸和", 1) }
        if context.isHaitei { add(context.isTsumo ? "海底摸月" : "河底撈魚", 1) }
        if context.isRinshan, context.isTsumo { add("嶺上開花", 1) }
        if context.isChankan, !context.isTsumo { add("槍槓", 1) }
        add("七対子", 2)
        if allTiles.allSatisfy({ TileKind.isSimple($0) }) { add("断ヤオ九", 1) }
        if allTiles.allSatisfy({ TileKind.isTerminalOrHonor($0) }) { add("混老頭", 2) }
        let suitsPresent = Set(allTiles.map { TileKind.suit(of: $0) })
        if suitsPresent.count <= 2, suitsPresent.filter({ $0 < 3 }).count == 1 {
            if suitsPresent.contains(3) {
                add("混一色", 3)
            } else {
                add("清一色", 6)
            }
        }
        let yakuHan = yaku.reduce(0) { $0 + $1.han }
        let dora = context.doraCount + input.redFives
        if dora > 0 { yaku.append(EvaluatedYaku(name: "ドラ", han: dora)) }
        return HandEvaluation(han: yakuHan + dora, fu: 25, yakumanCount: 0,
                              isChiitoitsu: true, yaku: yaku, dora: dora)
    }

    // MARK: 国士無双

    private static func evaluateKokushi(_ input: HandInput, counts: [Int]) -> HandEvaluation? {
        let terminals: [Int] = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]
        guard terminals.allSatisfy({ counts[$0] >= 1 }) else { return nil }
        guard (0...33).allSatisfy({ counts[$0] == 0 || terminals.contains($0) }) else { return nil }
        let thirteenWait = counts[input.winningTile] == 2
        return HandEvaluation(
            han: 0, fu: 40, yakumanCount: thirteenWait ? 2 : 1,
            isChiitoitsu: false,
            yaku: [EvaluatedYaku(name: thirteenWait ? "国士無双13面待ち" : "国士無双", han: 0)],
            dora: 0)
    }

    // MARK: 九蓮宝燈

    private static func evaluateChuuren(_ input: HandInput, counts: [Int]) -> HandEvaluation? {
        // 門前は呼び出し側の melds.isEmpty で保証
        let suits = Set(input.closedTiles.map { TileKind.suit(of: $0) })
        guard suits.count == 1, let suit = suits.first, suit < 3 else { return nil }
        let base = suit * 9
        guard counts[base] >= 3, counts[base + 8] >= 3 else { return nil }
        for offset in 1...7 where counts[base + offset] < 1 { return nil }
        // 純正: あがり牌を除いた13枚が 1112345678999
        var rest = counts
        rest[input.winningTile] -= 1
        let pattern = [3, 1, 1, 1, 1, 1, 1, 1, 3]
        let isPure = (0...8).allSatisfy { rest[base + $0] == pattern[$0] }
        return HandEvaluation(
            han: 0, fu: 40, yakumanCount: isPure ? 2 : 1,
            isChiitoitsu: false,
            yaku: [EvaluatedYaku(name: isPure ? "純正九蓮宝燈" : "九蓮宝燈", han: 0)],
            dora: 0)
    }
}
