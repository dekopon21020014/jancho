import MahjongScore
import SwiftUI

// MARK: - 牌フェイス（牌画素材：麻雀王国 https://mj-king.net/sozai/）

struct TileFace: View {
    let tile: Int
    var isRed: Bool = false
    var marked: Bool = false

    var body: some View {
        Group {
            if let image = faceImage {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                #else
                fallbackFace
                #endif
            } else {
                fallbackFace
            }
        }
        .frame(width: 31, height: 42)
        .overlay {
            if marked {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.accent, lineWidth: 2.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsRedBadge {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .overlay { Circle().stroke(Color.white, lineWidth: 1) }
                    .padding(1)
            }
        }
    }

    /// 赤5は改変した専用牌画を使い，専用牌画が無い場合だけ通常牌画になる
    private var faceImage: TilePlatformImage? {
        if isRed, let red = TileArt.redImage(for: tile) { return red }
        return TileArt.image(for: tile)
    }

    /// 専用牌画がある赤5ではバッジを重ねない
    private var showsRedBadge: Bool {
        isRed && TileArt.redImage(for: tile) == nil
    }

    /// 画像が読めない場合の代替表示
    private var fallbackFace: some View {
        Text(TileKind.name(of: tile))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: 31, height: 42)
            .background {
                RoundedRectangle(cornerRadius: 6).fill(Color.white)
            }
    }
}

// MARK: - 牌タップ入力

struct HandInputView: View {
    @Binding var evaluation: HandEvaluation?
    let isTsumo: Bool
    var isSanma: Bool = false
    let seatWind: Int
    let roundWind: Int
    @Binding var riichi: Bool

    private struct Pick: Identifiable, Equatable {
        let id = UUID()
        var tile: Int
        var isRed: Bool
    }

    private struct MeldPick: Identifiable, Equatable {
        let id = UUID()
        var meld: Meld
        var hasRed: Bool
    }

    @State private var picks: [Pick] = []
    @State private var winningID: UUID?
    @State private var meldPicks: [MeldPick] = []
    @State private var meldMode: Meld.Kind?
    @State private var doubleRiichi = false
    @State private var ippatsu = false
    @State private var haitei = false
    @State private var rinshan = false
    @State private var chankan = false
    @State private var doraIndicators: [Int] = []
    @State private var uraIndicators: [Int] = []
    @State private var indicatorTarget: IndicatorTarget?
    @State private var kita = 0

    /// パレットで選んでいる表示牌の種類
    private enum IndicatorTarget {
        case dora, ura
    }

    private var totalTiles: Int { picks.count + meldPicks.count * 3 }
    private var isComplete: Bool { totalTiles == 14 }

    /// 表示牌に対応するドラが手牌（副露含む）に何枚あるか
    private func countDora(from indicators: [Int]) -> Int {
        let targets = indicators.map(TileKind.doraTile(fromIndicator:))
        guard !targets.isEmpty else { return 0 }
        var count = 0
        for pick in picks where targets.contains(pick.tile) { count += 1 }
        for meldPick in meldPicks {
            for tile in meldPick.meld.tiles where targets.contains(tile) { count += 1 }
        }
        return count
    }

    private var indicatorDora: Int { countDora(from: doraIndicators) }
    /// 裏ドラはリーチのときだけ数える
    private var uraDora: Int { riichi ? countDora(from: uraIndicators) : 0 }
    /// ドラ合計（赤5は含まない．赤5は評価側で自動加算される）
    private var totalDora: Int { indicatorDora + uraDora + (isSanma ? kita : 0) }

    private var doraSummaryText: String {
        var parts = ["表示 \(indicatorDora)"]
        if riichi { parts.append("裏 \(uraDora)") }
        if isSanma { parts.append("北抜き \(kita)") }
        return "ドラ合計 \(totalDora)（\(parts.joined(separator: "・"))）．赤5は自動で加算されます．"
    }

    private func copyCount(of tile: Int) -> Int {
        var count = picks.filter { $0.tile == tile }.count
        for meldPick in meldPicks {
            count += meldPick.meld.tiles.filter { $0 == tile }.count
        }
        return count
    }

    // MARK: 入力操作

    private func tapPalette(_ tile: Int, asRed: Bool = false) {
        if indicatorTarget != nil {
            addIndicator(tile)
            return
        }
        if let mode = meldMode {
            addMeld(kind: mode, base: tile, asRed: asRed)
            return
        }
        guard totalTiles < 14, copyCount(of: tile) < 4 else { return }
        let suit = TileKind.suit(of: tile)
        let isRed = asRed && suit < 3 && TileKind.rank(of: tile) == 5
        let pick = Pick(tile: tile, isRed: isRed)
        picks.append(pick)
        winningID = pick.id
        refresh()
    }

    private func addIndicator(_ tile: Int) {
        guard let target = indicatorTarget else { return }
        let list = target == .dora ? doraIndicators : uraIndicators
        guard list.count < 5 else { return }
        // 表示牌は山の牌なので，手牌・副露・他の表示牌と合わせて4枚まで
        let inIndicators = (doraIndicators + uraIndicators).filter { $0 == tile }.count
        guard copyCount(of: tile) + inIndicators < 4 else { return }
        if target == .dora {
            doraIndicators.append(tile)
        } else {
            uraIndicators.append(tile)
        }
        refresh()
    }

    private func removeIndicator(at index: Int, target: IndicatorTarget) {
        if target == .dora {
            doraIndicators.remove(at: index)
        } else {
            uraIndicators.remove(at: index)
        }
        refresh()
    }

    private func toggleIndicatorTarget(_ target: IndicatorTarget) {
        if indicatorTarget == target {
            indicatorTarget = nil
        } else {
            indicatorTarget = target
            meldMode = nil
        }
    }

    private func addMeld(kind: Meld.Kind, base: Int, asRed: Bool = false) {
        let meld = Meld(kind: kind, tile: base)
        if kind == .shuntsu {
            guard TileKind.suit(of: base) < 3, TileKind.rank(of: base) <= 7 else { return }
        }
        guard totalTiles + 3 <= 14 else { return }
        for tile in meld.tiles where copyCount(of: tile) + meld.tiles.filter({ $0 == tile }).count > 4 {
            return
        }
        let containsFive = meld.tiles.contains { TileKind.suit(of: $0) < 3 && TileKind.rank(of: $0) == 5 }
        let suit = TileKind.suit(of: base)
        let hasRed = asRed && containsFive
        meldPicks.append(MeldPick(meld: meld, hasRed: hasRed))
        meldMode = nil
        refresh()
    }

    private func tapPick(_ pick: Pick) {
        if winningID == pick.id {
            picks.removeAll { $0.id == pick.id }
            winningID = picks.last?.id
        } else {
            winningID = pick.id
        }
        refresh()
    }

    private func refresh() {
        guard isComplete, let winning = picks.first(where: { $0.id == winningID }) else {
            evaluation = nil
            return
        }
        var input = HandInput()
        input.closedTiles = picks.map(\.tile)
        input.redFives = picks.filter(\.isRed).count + meldPicks.filter(\.hasRed).count
        input.melds = meldPicks.map(\.meld)
        input.winningTile = winning.tile
        input.context.isTsumo = isTsumo
        input.context.isRiichi = riichi
        input.context.isDoubleRiichi = doubleRiichi
        input.context.isIppatsu = ippatsu
        input.context.isHaitei = haitei
        input.context.isRinshan = rinshan
        input.context.isChankan = chankan
        input.context.seatWind = seatWind
        input.context.roundWind = roundWind
        input.context.doraCount = totalDora
        evaluation = HandEvaluator.evaluate(input)
    }

    // MARK: 画面

    var body: some View {
        VStack(spacing: 18) {
            handCard
            meldCard
            paletteCard
            situationCard
            resultCard
        }
        .onChange(of: isTsumo) { refresh() }
        .onChange(of: seatWind) { refresh() }
        .onChange(of: roundWind) { refresh() }
        .onChange(of: riichi) { refresh() }
        .onAppear { refresh() }
    }

    private var handCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "手牌（\(totalTiles) / 14）", systemImage: "square.grid.3x3")
            TileCard {
                VStack(alignment: .leading, spacing: 10) {
                    if picks.isEmpty {
                        Text("下のパレットから牌をタップして追加．")
                            .font(.caption)
                            .foregroundStyle(Theme.subInk)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 31), spacing: 5)],
                            alignment: .leading, spacing: 5
                        ) {
                            ForEach(picks) { pick in
                                Button {
                                    tapPick(pick)
                                } label: {
                                    TileFace(tile: pick.tile, isRed: pick.isRed,
                                             marked: pick.id == winningID)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(TileKind.name(of: pick.tile))
                            }
                        }
                        Text("赤い枠が あがり牌．タップで指定，もう一度タップで削除．")
                            .font(.caption2)
                            .foregroundStyle(Theme.subInk)
                    }
                    if !picks.isEmpty {
                        Button("手牌をクリア", role: .destructive) {
                            picks = []
                            winningID = nil
                            refresh()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private var meldCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "副露", systemImage: "rectangle.stack")
            TileCard {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(meldPicks) { meldPick in
                        HStack(spacing: 6) {
                            Text(meldLabel(meldPick.meld.kind))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.green)
                                .frame(width: 36, alignment: .leading)
                            ForEach(Array(meldPick.meld.tiles.enumerated()), id: \.offset) { _, tile in
                                TileFace(
                                    tile: tile,
                                    isRed: meldPick.hasRed
                                        && TileKind.suit(of: tile) < 3
                                        && TileKind.rank(of: tile) == 5)
                            }
                            Spacer()
                            if meldPick.meld.tiles.contains(where: { TileKind.suit(of: $0) < 3 && TileKind.rank(of: $0) == 5 }) {
                                Button {
                                    toggleMeldRed(meldPick)
                                } label: {
                                    Text("赤")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background {
                                            Capsule().fill(meldPick.hasRed ? Color.red : Color.gray.opacity(0.5))
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                meldPicks.removeAll { $0.id == meldPick.id }
                                refresh()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.subInk)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 8) {
                        meldButton("ポン", kind: .pon)
                        if !isSanma {
                            meldButton("チー", kind: .shuntsu)
                        }
                        meldButton("明槓", kind: .minkan)
                        meldButton("暗槓", kind: .ankan)
                    }
                    if isSanma {
                        Text("三麻ルール：チーはできません．北抜きはパレット下の「北抜き」で数えます．")
                            .font(.caption2)
                            .foregroundStyle(Theme.subInk)
                    }
                    if meldMode != nil {
                        Text("パレットで面子の牌をタップ（チーは一番小さい牌）．")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    private func meldLabel(_ kind: Meld.Kind) -> String {
        switch kind {
        case .pon: return "ポン"
        case .shuntsu: return "チー"
        case .minkan: return "明槓"
        case .ankan: return "暗槓"
        }
    }

    private func meldButton(_ title: String, kind: Meld.Kind) -> some View {
        Chip(title: title, selected: meldMode == kind, accent: Theme.green) {
            indicatorTarget = nil
            meldMode = meldMode == kind ? nil : kind
        }
    }

    private var paletteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: paletteTitle, systemImage: "hand.tap")
            TileCard {
                VStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { suit in
                        HStack(spacing: 4) {
                            ForEach(paletteTiles(suit: suit), id: \.self) { tile in
                                Button {
                                    tapPalette(tile)
                                } label: {
                                    TileFace(tile: tile)
                                }
                                .buttonStyle(.plain)
                                .opacity(copyCount(of: tile) >= 4 ? 0.3 : 1)
                                .accessibilityLabel(TileKind.name(of: tile))
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(redPaletteTiles, id: \.self) { tile in
                            Button {
                                tapPalette(tile, asRed: true)
                            } label: {
                                TileFace(tile: tile, isRed: true)
                            }
                            .buttonStyle(.plain)
                            .opacity(redUnavailable(tile) ? 0.3 : 1)
                            .accessibilityLabel("赤" + TileKind.name(of: tile))
                        }
                        Spacer()
                    }
                    Divider()
                    indicatorRow(title: "ドラ表示牌", indicators: doraIndicators, target: .dora)
                    indicatorRow(title: "裏ドラ表示牌", indicators: uraIndicators, target: .ura)
                    if isSanma {
                        HStack {
                            Text("北抜き")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.subInk)
                                .frame(width: 74, alignment: .leading)
                            Spacer()
                            Button {
                                if kita > 0 { kita -= 1; refresh() }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            Text("\(kita)")
                                .font(.headline)
                                .frame(width: 28)
                            Button {
                                if kita < 4 { kita += 1; refresh() }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(doraSummaryText)
                        .font(.caption2)
                        .foregroundStyle(Theme.subInk)
                    if indicatorTarget != nil {
                        Text("パレットで表示牌をタップ．表示牌をタップすると取り消します．")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                    Text("牌画素材：麻雀王国（mj-king.net）")
                        .font(.caption2)
                        .foregroundStyle(Theme.subInk)
                }
            }
        }
    }

    /// 赤5のパレット並び（三麻では五萬は存在しないので出さない）
    private var redPaletteTiles: [Int] { isSanma ? [13, 22] : [4, 13, 22] }

    /// 赤5がもう選べない状態か（その牌が4枚とも使用済み）
    private func redUnavailable(_ tile: Int) -> Bool {
        copyCount(of: tile) >= 4
    }

    /// 副露の赤5の有無を切り替える（順子の5など，パレットの赤から直接作れない場合用）
    private func toggleMeldRed(_ meldPick: MeldPick) {
        guard let index = meldPicks.firstIndex(where: { $0.id == meldPick.id }) else { return }
        meldPicks[index].hasRed.toggle()
        refresh()
    }

    private var paletteTitle: String {
        if indicatorTarget == .dora { return "ドラ表示牌を選ぶ" }
        if indicatorTarget == .ura { return "裏ドラ表示牌を選ぶ" }
        return meldMode != nil ? "面子の牌を選ぶ" : "牌を選ぶ"
    }

    private func indicatorRow(title: String, indicators: [Int], target: IndicatorTarget) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.subInk)
                .frame(width: 74, alignment: .leading)
            ForEach(Array(indicators.enumerated()), id: \.offset) { index, tile in
                Button {
                    removeIndicator(at: index, target: target)
                } label: {
                    TileFace(tile: tile)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TileKind.name(of: tile))
            }
            Button {
                toggleIndicatorTarget(target)
            } label: {
                Image(systemName: indicatorTarget == target ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(indicatorTarget == target ? Theme.accent : Theme.green)
            }
            .buttonStyle(.plain)
            Spacer()
            if target == .ura && !riichi {
                Text("リーチ時のみ有効")
                    .font(.caption2)
                    .foregroundStyle(Theme.subInk)
            }
        }
    }

    private func paletteTiles(suit: Int) -> [Int] {
        if suit == 0 && isSanma {
            // 三人打ちの萬子は1と9のみ
            return [0, 8]
        }
        return suit < 3 ? Array(suit * 9..<(suit * 9 + 9)) : Array(27...33)
    }

    private var situationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "状況", systemImage: "flag")
            TileCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Chip(title: "リーチ", selected: riichi, accent: Theme.accent) {
                            riichi.toggle()
                            if !riichi { doubleRiichi = false; ippatsu = false }
                            refresh()
                        }
                        Chip(title: "ダブルリーチ", selected: doubleRiichi, accent: Theme.accent) {
                            doubleRiichi.toggle()
                            if doubleRiichi { riichi = true } else { refresh() }
                            refresh()
                        }
                        Chip(title: "一発", selected: ippatsu, accent: Theme.accent) {
                            ippatsu.toggle()
                            refresh()
                        }
                    }
                    HStack(spacing: 8) {
                        Chip(title: isTsumo ? "海底摸月" : "河底撈魚", selected: haitei, accent: Theme.green) {
                            haitei.toggle()
                            refresh()
                        }
                        if isTsumo {
                            Chip(title: "嶺上開花", selected: rinshan, accent: Theme.green) {
                                rinshan.toggle()
                                refresh()
                            }
                        } else {
                            Chip(title: "槍槓", selected: chankan, accent: Theme.green) {
                                chankan.toggle()
                                refresh()
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        if isComplete {
            VStack(alignment: .leading, spacing: 10) {
                FeltLabel(title: "判定結果", systemImage: "checkmark.seal")
                TileCard {
                    if let evaluation {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(evaluation.yaku.enumerated()), id: \.offset) { _, yaku in
                                HStack {
                                    Text(yaku.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(evaluation.yakumanCount > 0 ? "" : "\(yaku.han) 翻")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.subInk)
                                }
                            }
                            Divider()
                            HStack {
                                Text("合計")
                                    .font(.headline)
                                Spacer()
                                Text(totalText(evaluation))
                                    .font(.headline)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    } else {
                        Text("役がありません．形があがりの形になっていないか，役なしです．")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    private func totalText(_ evaluation: HandEvaluation) -> String {
        if evaluation.yakumanCount > 0 {
            return evaluation.yakumanCount == 1 ? "役満" : "\(evaluation.yakumanCount)倍役満"
        }
        return "\(evaluation.han) 翻 \(evaluation.fu) 符"
    }
}
