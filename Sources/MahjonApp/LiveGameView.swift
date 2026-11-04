import MahjongScore
import SwiftData
import SwiftUI

// MARK: - 対局状態

struct PlayerState: Codable, Equatable {
    var name: String = ""
    var score: Int = 25000
    var isRiichi: Bool = false
}

struct LiveGameState: Codable, Equatable {
    var players: [PlayerState] = []
    /// 親のプレイヤー番号
    var dealerIndex: Int = 0
    /// 東1局を0とする通しの局数（連荘では増えない）
    var handNumber: Int = 0
    var honba: Int = 0
    /// 供託リーチ棒の本数
    var riichiSticks: Int = 0
    var gameType: String = "半荘"
    var startScore: Int = 25000
    /// pt換算の返し点（結果画面用．対局設定で変更可）
    var returnScore: Int = 30000
    /// ウマ（pt）．デフォルトはなし（0）．
    /// 4人打ちは1位と2位の値（3位は-2位，4位は-1位），
    /// 3人打ちは1位の値のみ使う（2位は0，3位は-1位）
    var umaFirst: Int = 0
    var umaSecond: Int = 0
    /// オカの有無．デフォルトはなし．
    /// オカは (返し点-開始点)×人数/1000 を1位に加算する
    var okaEnabled: Bool = false
    /// 三麻ルールかどうか（人数とは独立に選ぶ）．
    /// 旧セーブにキーが無い場合にデコードが失敗しないようOptionalで保持する
    var sanmaRules: Bool? = nil
    var isStarted: Bool = false
    var isFinished: Bool = false

    /// 三麻ルール適用中か（萬子は1・9のみ，チー不可，北は抜きドラ）．
    /// 未設定（旧形式のセーブ）のときは3人対局を三麻として扱う
    var isSanmaRules: Bool { sanmaRules ?? (players.count == 3) }

    /// 1周あたりの局数（=人数）．未開始（players空）のときは4
    var perRound: Int { players.isEmpty ? 4 : players.count }

    var totalHands: Int { (gameType == "東風" ? 1 : 2) * perRound }
    var windName: String { ["東", "南", "西", "北"][min(handNumber / perRound, 3)] }
    var kyoku: Int { handNumber % perRound + 1 }
    var roundLabel: String { "\(windName)\(kyoku)局" }

    /// この局に打つ人数．四麻は4人，三麻は3人（参加人数が上限）．
    /// 残りの参加者は抜け番（回し打ち）で，その局の点数のやり取りに参加しない
    var playingCount: Int { min(players.count, isSanmaRules ? 3 : 4) }

    /// 親から数えた席順（0=親）．抜け番判定に使う
    func seatOffset(of index: Int) -> Int {
        players.isEmpty ? 0 : (index - dealerIndex + players.count) % players.count
    }

    /// この局に打っているか（抜け番でないか）
    func isPlaying(_ index: Int) -> Bool {
        seatOffset(of: index) < playingCount
    }

    /// この局に打っている人のプレイヤー番号（親から席順）
    var playingIndices: [Int] {
        guard !players.isEmpty else { return [] }
        return (0..<playingCount).map { (dealerIndex + $0) % players.count }
    }

    func seatWind(of index: Int) -> String {
        // 打っている人の席風．四麻は東西南北，三麻は東西南まで．抜け番は「抜」
        let offset = seatOffset(of: index)
        guard offset < playingCount else { return "抜" }
        return ["東", "南", "西", "北"][offset]
    }

    var leaderIndex: Int? {
        players.indices.max { players[$0].score < players[$1].score }
    }
}

/// あがり申告の内容
struct WinDeclaration {
    var winner: Int
    var method: WinMethod
    var discarder: Int?
    var han: Int
    var fu: Int
    var chiitoitsu: Bool
    var yakuman: Int
    /// その局にリーチしていた人（あがり画面の供託項目で記録．精算前に点数へ反映する）
    var riichiPlayers: Set<Int> = []
}

private struct LiveGameStore: Codable {
    var game: LiveGameState
    var snapshots: [LiveGameState]
}

private let liveGameKey = "liveGame.v1"

/// 正N角形（頂点の1つが真下）の輪郭
struct PolygonShape: Shape {
    var sides: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<sides {
            let angle = 2 * Double.pi * Double(i) / Double(sides)
            let point = CGPoint(
                x: rect.midX + rect.width / 2 * CGFloat(sin(angle)),
                y: rect.midY + rect.height / 2 * CGFloat(cos(angle)))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - 対局タブ

struct LiveGameView: View {
    @State private var game = LiveGameState()
    @State private var snapshots: [LiveGameState] = []
    @State private var sheet: LiveSheet?
    @State private var loaded = false

    enum LiveSheet: Identifiable {
        case win, draw, results
        case player(Int)

        var id: String {
            switch self {
            case .win: return "win"
            case .draw: return "draw"
            case .results: return "results"
            case .player(let index): return "player-\(index)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                if game.isStarted {
                    board
                } else {
                    LiveSetupView { configured in
                        game = configured
                        snapshots = []
                        save()
                    }
                }
            }
            .navigationTitle("対局")
            .toolbar {
                if game.isStarted {
                    ToolbarItem(placement: .primaryAction) {
                        Button("結果") { sheet = .results }
                    }
                }
            }
            .sheet(item: $sheet) { item in
                switch item {
                case .win:
                    WinFlowView(game: game) { declaration in
                        applyWin(declaration)
                        return game
                    }
                case .draw:
                    DrawFlowView(game: game) { tenpai, nagashi in
                        applyDraw(tenpai, nagashi: nagashi)
                        return game
                    }
                case .player(let index):
                    PlayerActionView(
                        player: game.players[index],
                        isDealer: index == game.dealerIndex,
                        seatWind: game.seatWind(of: index),
                        isPlaying: game.isPlaying(index),
                        onRiichi: { toggleRiichi(index) },
                        onCorrect: { adjustScore(index, to: $0) }
                    )
                case .results:
                    GameResultsView(
                        game: game,
                        onContinue: {
                            game.isFinished = false
                            save()
                        },
                        onReset: {
                            game = LiveGameState()
                            snapshots = []
                            save()
                        }
                    )
                }
            }
            .onAppear {
                if !loaded {
                    load()
                    loaded = true
                }
            }
        }
    }

    // MARK: ボード

    private var board: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                tableArea
                actionBar
                Text("プレイヤーのカードをタップすると，リーチ宣言や点数修正ができます．")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(16)
        }
    }

    private var statusCard: some View {
        TileCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.roundLabel)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("\(game.honba) 本場")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.subInk)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.caption)
                        Text("供託 \(game.riichiSticks) 本")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(game.riichiSticks > 0 ? Theme.accent : Theme.subInk)
                    if let leader = game.leaderIndex {
                        Text("トップ \(game.players[leader].name) \(game.players[leader].score)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.subInk)
                    }
                }
            }
            if game.isFinished {
                Text("対局終了．「結果」から成績に保存できます．")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 8)
            }
        }
    }

    /// プレイヤーを正N角形の頂点に配置する卓レイアウト（起家が下の頂点）
    private var tableArea: some View {
        GeometryReader { geo in
            let count = game.perRound
            let width = geo.size.width
            let height = geo.size.height
            // 人数が多いほどカードを小さくして，頂点同士の重なりを防ぐ
            let cardWidth: CGFloat = count >= 7 ? 100 : count == 6 ? 104 : count == 5 ? 108 : 130
            let cardHeight: CGFloat = count > 4 ? 68 : 96
            let rx = max(0, width / 2 - cardWidth / 2 - 2)
            let ry = max(0, height / 2 - cardHeight / 2 - 2)
            ZStack {
                PolygonShape(sides: count)
                    .stroke(.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: rx * 2, height: ry * 2)
                    .position(x: width / 2, y: height / 2)
                centerTile
                    .position(x: width / 2, y: height / 2)
                ForEach(0..<count, id: \.self) { offset in
                    let angle = 2 * Double.pi * Double(offset) / Double(count)
                    playerTile(index: rel(offset), compact: offset != 0)
                        .frame(width: offset == 0 ? cardWidth + (count > 4 ? 14 : 26) : cardWidth)
                        .position(
                            x: width / 2 + rx * CGFloat(sin(angle)),
                            y: height / 2 + ry * CGFloat(cos(angle)))
                }
            }
        }
        .frame(height: tableHeight)
    }

    /// 卓エリアの高さ．人数が多いほど縦にも広げて重なりを防ぐ
    private var tableHeight: CGFloat {
        switch game.perRound {
        case 5: return 430
        case 6: return 450
        case 7...: return 470
        default: return 370
        }
    }

    /// 卓の頂点位置→プレイヤー番号．起家（プレイヤー1）を下の頂点に固定する
    private func rel(_ offset: Int) -> Int {
        offset % game.perRound
    }

    private var centerTile: some View {
        VStack(spacing: 2) {
            Text(game.windName)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
            Text("\(game.kyoku)局")
                .font(.caption.weight(.bold))
            Text("\(game.honba)本場")
                .font(.caption2)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(width: 74, height: 74)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.35))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                }
        }
    }

    /// カード右上のリーチ（供託）トグル．画面遷移なしで宣言・取り消しできる
    private func riichiToggle(index: Int, mini: Bool) -> some View {
        let player = game.players[index]
        let canDeclare = player.isRiichi || player.score >= 1000
        return Button {
            toggleRiichi(index)
        } label: {
            Text("リーチ")
                .font(mini ? .system(size: 9, weight: .heavy) : .caption2.weight(.heavy))
                .foregroundStyle(player.isRiichi ? .white : Theme.subInk)
                .padding(.horizontal, mini ? 6 : 7)
                .padding(.vertical, mini ? 3 : 4)
                .background {
                    Capsule().fill(player.isRiichi ? Theme.accent : Color.black.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
        .disabled(!canDeclare)
        .opacity(canDeclare ? 1 : 0.45)
    }

    private func playerTile(index: Int, compact: Bool) -> some View {
        let player = game.players[index]
        let isDealer = index == game.dealerIndex
        return Button {
            sheet = .player(index)
        } label: {
            TileCard(padding: game.perRound >= 5 ? 7 : (compact ? 9 : 12)) {
                if game.perRound >= 5 {
                    // 多人数打ち用の小さなカード（差分表示は省略）
                    VStack(spacing: 3) {
                        HStack(spacing: 4) {
                            Text(game.seatWind(of: index))
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background {
                                    Circle().fill(isDealer ? Theme.accent : Theme.green)
                                }
                            Text(player.name)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                        }
                        .padding(.trailing, 26)
                        Text("\(player.score)")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(player.score < 0 ? Theme.accent : Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(game.seatWind(of: index))
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background {
                                Circle().fill(isDealer ? Theme.accent : Theme.green)
                            }
                        Spacer()
                    }
                    Text(player.name)
                        .font(compact ? .subheadline.weight(.bold) : .headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("\(player.score)")
                        .font(.system(size: compact ? 22 : 27, weight: .heavy, design: .rounded))
                        .foregroundStyle(player.score < 0 ? Theme.accent : Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    let diff = player.score - game.startScore
                    Text(diff >= 0 ? "+\(diff)" : "\(diff)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(diff >= 0 ? Theme.green : Theme.accent)
                }
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            // 抜け番の人にはリーチトグルを出さない
            if game.isPlaying(index) {
                riichiToggle(index: index, mini: game.perRound >= 5)
                    .padding(game.perRound >= 5 ? 5 : 8)
            }
        }
        .opacity(game.isPlaying(index) ? 1 : 0.55)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                sheet = .win
            } label: {
                Text("あがり")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Theme.accent)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 3)
                    }
            }
            .buttonStyle(.plain)
            Button {
                sheet = .draw
            } label: {
                Text("流局")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 22)
                    .background {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Theme.green)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 3)
                    }
            }
            .buttonStyle(.plain)
            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 16)
                    .background {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.35))
                    }
            }
            .buttonStyle(.plain)
            .disabled(snapshots.isEmpty)
            .opacity(snapshots.isEmpty ? 0.45 : 1)
        }
    }

    // MARK: 精算

    private func applyWin(_ declaration: WinDeclaration) {
        // あがり画面の供託項目を先に反映する（新規リーチは-1000，取り消しは+1000）
        // 供託はこの局に打っている人だけが対象
        let riichiPlayers = declaration.riichiPlayers.intersection(Set(game.playingIndices))
        for index in game.players.indices {
            let declared = riichiPlayers.contains(index)
            if declared != game.players[index].isRiichi {
                game.players[index].isRiichi = declared
                game.players[index].score += declared ? -1000 : 1000
            }
        }
        game.riichiSticks = riichiPlayers.count
        let result = ScoreCalculator.calculate(ScoreInput(
            han: declaration.han, fu: declaration.fu,
            isDealer: declaration.winner == game.dealerIndex,
            winMethod: declaration.method,
            honba: game.honba, riichiSticks: game.riichiSticks,
            isChiitoitsu: declaration.chiitoitsu, yakumanCount: declaration.yakuman,
            playerCount: game.playingCount))
        commit()
        switch declaration.method {
        case .ron:
            if let discarder = declaration.discarder, let payment = result.ronPayment {
                game.players[discarder].score -= payment
            }
        case .tsumo:
            // ツモの支払いはこの局に打っている人だけ
            for index in game.playingIndices where index != declaration.winner {
                let payment: Int
                if declaration.winner == game.dealerIndex || index == game.dealerIndex {
                    payment = result.tsumoDealerPayment ?? 0
                } else {
                    payment = result.tsumoChildPayment ?? 0
                }
                game.players[index].score -= payment
            }
        }
        game.players[declaration.winner].score += result.totalReceived
        game.riichiSticks = 0
        for index in game.players.indices { game.players[index].isRiichi = false }
        if declaration.winner == game.dealerIndex {
            game.honba += 1
        } else {
            game.honba = 0
            advanceHand()
        }
        save()
    }

    private func applyDraw(_ tenpai: Set<Int>, nagashi: Int?) {
        commit()
        if let nagashi {
            // 流し満貫：満貫ツモ相当の精算．供託リーチ棒は持ち越し，テンパイ料はなし
            let result = ScoreCalculator.calculate(ScoreInput(
                han: 5, fu: 30,
                isDealer: nagashi == game.dealerIndex,
                winMethod: .tsumo,
                honba: game.honba, riichiSticks: 0,
                playerCount: game.playingCount))
            for index in game.playingIndices where index != nagashi {
                let payment = nagashi == game.dealerIndex || index == game.dealerIndex
                    ? (result.tsumoDealerPayment ?? 0)
                    : (result.tsumoChildPayment ?? 0)
                game.players[index].score -= payment
            }
            game.players[nagashi].score += result.totalReceived
            for index in game.players.indices { game.players[index].isRiichi = false }
            game.honba += 1
            if nagashi != game.dealerIndex {
                advanceHand()
            }
            save()
            return
        }
        if tenpai.count > 0 && tenpai.count < game.playingCount {
            let gain = 3000 / tenpai.count
            let loss = 3000 / (game.playingCount - tenpai.count)
            for index in game.playingIndices {
                game.players[index].score += tenpai.contains(index) ? gain : -loss
            }
        }
        for index in game.players.indices { game.players[index].isRiichi = false }
        game.honba += 1
        if !tenpai.contains(game.dealerIndex) {
            advanceHand()
        }
        save()
    }

    private func advanceHand() {
        game.handNumber += 1
        game.dealerIndex = (game.dealerIndex + 1) % game.perRound
        if game.handNumber >= game.totalHands {
            game.isFinished = true
        }
    }

    private func toggleRiichi(_ index: Int) {
        // 抜け番の人はリーチできない
        guard game.isPlaying(index) else { return }
        if game.players[index].isRiichi {
            commit()
            game.players[index].isRiichi = false
            game.players[index].score += 1000
            game.riichiSticks = max(0, game.riichiSticks - 1)
            save()
        } else if game.players[index].score >= 1000 {
            commit()
            game.players[index].isRiichi = true
            game.players[index].score -= 1000
            game.riichiSticks += 1
            save()
        }
    }

    private func adjustScore(_ index: Int, to newScore: Int) {
        commit()
        game.players[index].score = newScore
        save()
    }

    // MARK: 保存・復元・取り消し

    private func commit() {
        snapshots.append(game)
        if snapshots.count > 50 { snapshots.removeFirst() }
    }

    private func undo() {
        guard let previous = snapshots.popLast() else { return }
        game = previous
        save()
    }

    private func save() {
        let store = LiveGameStore(game: game, snapshots: snapshots)
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: liveGameKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: liveGameKey),
           let store = try? JSONDecoder().decode(LiveGameStore.self, from: data) {
            game = store.game
            snapshots = store.snapshots
        }
    }
}

// MARK: - 対局設定

struct LiveSetupView: View {
    var onStart: (LiveGameState) -> Void

    @State private var names = ["", "", "", "", "", "", ""]
    @State private var gameType = "半荘"
    @State private var startScore = 25000
    @State private var playerCount = 4
    @State private var sanmaRules = false
    @State private var returnScore = 30000
    @State private var umaFirst = 0
    @State private var umaSecond = 0
    @State private var okaEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    FeltLabel(title: "プレイヤー", systemImage: "person.3")
                    TileCard {
                        VStack(spacing: 10) {
                            ForEach(0..<playerCount, id: \.self) { index in
                                HStack(spacing: 8) {
                                    Text(["東", "南", "西", "北", "白", "發", "中"][index])
                                        .font(.headline)
                                        .foregroundStyle(Theme.subInk)
                                        .frame(width: 22)
                                    TextField("プレイヤー\(index + 1)", text: $names[index])
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                }
                                if index < playerCount - 1 { Divider() }
                            }
                        }
                    }
                    Text("入力した順に起家（東）から座ります．成績への保存は，結果画面でプレイヤーごとに行います．")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                VStack(alignment: .leading, spacing: 10) {
                    FeltLabel(title: "ルール", systemImage: "gearshape")
                    TileCard {
                        VStack(alignment: .leading, spacing: 12) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                                ForEach(3...7, id: \.self) { count in
                                    Chip(title: "\(count)人", selected: playerCount == count,
                                         accent: Theme.green) {
                                        playerCount = count
                                    }
                                }
                            }
                            HStack(spacing: 8) {
                                Chip(title: "東風", selected: gameType == "東風") { gameType = "東風" }
                                Chip(title: "半荘", selected: gameType == "半荘") { gameType = "半荘" }
                            }
                            HStack(spacing: 12) {
                                BigToggle(title: "四麻", subtitle: "通常の牌・チーあり", selected: !sanmaRules, accent: Theme.green) {
                                    sanmaRules = false
                                    startScore = 25000
                                    returnScore = 30000
                                }
                                BigToggle(title: "三麻", subtitle: "萬子1・9のみ・チーなし", selected: sanmaRules, accent: Theme.gold) {
                                    sanmaRules = true
                                    startScore = 35000
                                    returnScore = 40000
                                }
                            }
                            Text("人数とルールは別々に選べます（4人で三麻もできます）．打つのは四麻4人・三麻3人で，残りは抜け番（回し打ち）になります．")
                                .font(.caption2)
                                .foregroundStyle(Theme.subInk)
                            HStack(spacing: 8) {
                                Chip(title: "25000 点", selected: startScore == 25000) {
                                    startScore = 25000
                                    returnScore = 30000
                                }
                                Chip(title: "30000 点", selected: startScore == 30000) {
                                    startScore = 30000
                                    returnScore = 35000
                                }
                                Chip(title: "35000 点", selected: startScore == 35000) {
                                    startScore = 35000
                                    returnScore = 40000
                                }
                            }
                        }
                    }
                }
                if playerCount == 3 || playerCount == 4 {
                    VStack(alignment: .leading, spacing: 10) {
                        FeltLabel(title: "pt換算", systemImage: "chart.bar")
                        TileCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text("返し")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Chip(title: "−1000", selected: false) {
                                        returnScore = max(startScore, returnScore - 1000)
                                    }
                                    Text("\(returnScore) 点")
                                        .font(.headline)
                                        .foregroundStyle(Theme.ink)
                                        .frame(minWidth: 76)
                                    Chip(title: "+1000", selected: false) {
                                        returnScore += 1000
                                    }
                                }
                                HStack(spacing: 8) {
                                    Text("ウマ")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Theme.ink)
                                    if playerCount == 4 {
                                        Chip(title: "10-20", selected: umaFirst == 20 && umaSecond == 10) {
                                            umaFirst = 20
                                            umaSecond = 10
                                        }
                                        Chip(title: "10-30", selected: umaFirst == 30 && umaSecond == 10) {
                                            umaFirst = 30
                                            umaSecond = 10
                                        }
                                        Chip(title: "20-30", selected: umaFirst == 30 && umaSecond == 20) {
                                            umaFirst = 30
                                            umaSecond = 20
                                        }
                                        Chip(title: "5-10", selected: umaFirst == 10 && umaSecond == 5) {
                                            umaFirst = 10
                                            umaSecond = 5
                                        }
                                    } else {
                                        Chip(title: "20-0-20", selected: umaFirst == 20) {
                                            umaFirst = 20
                                            umaSecond = 0
                                        }
                                        Chip(title: "30-0-30", selected: umaFirst == 30) {
                                            umaFirst = 30
                                            umaSecond = 0
                                        }
                                        Chip(title: "10-0-10", selected: umaFirst == 10) {
                                            umaFirst = 10
                                            umaSecond = 0
                                        }
                                    }
                                    Chip(title: "なし", selected: umaFirst == 0) {
                                        umaFirst = 0
                                        umaSecond = 0
                                    }
                                }
                                HStack(spacing: 8) {
                                    Text("オカ")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Theme.ink)
                                    Chip(title: "あり", selected: okaEnabled) { okaEnabled = true }
                                    Chip(title: "なし", selected: !okaEnabled) { okaEnabled = false }
                                    if okaEnabled {
                                        Text("1位に +\((returnScore - startScore) * playerCount / 1000) pt")
                                            .font(.caption)
                                            .foregroundStyle(Theme.subInk)
                                    }
                                }
                            }
                        }
                        Text("結果画面のpt換算に使います．5人以上は素点のみで，この設定は使いません．")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                Button {
                    var state = LiveGameState()
                    state.players = (0..<playerCount).map { index in
                        PlayerState(
                            name: names[index].isEmpty ? "プレイヤー\(index + 1)" : names[index],
                            score: startScore)
                    }
                    state.gameType = gameType
                    state.sanmaRules = sanmaRules
                    state.startScore = startScore
                    state.returnScore = returnScore
                    state.umaFirst = umaFirst
                    state.umaSecond = umaSecond
                    state.okaEnabled = okaEnabled
                    state.isStarted = true
                    onStart(state)
                } label: {
                    Text("対局開始")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.accent)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 3)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }
}

// MARK: - プレイヤー操作

struct PlayerActionView: View {
    let player: PlayerState
    let isDealer: Bool
    let seatWind: String
    /// この局に打っているか．抜け番の人はリーチできない
    let isPlaying: Bool
    var onRiichi: () -> Void
    var onCorrect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var correctedScore: Int

    init(player: PlayerState, isDealer: Bool, seatWind: String, isPlaying: Bool,
         onRiichi: @escaping () -> Void, onCorrect: @escaping (Int) -> Void) {
        self.player = player
        self.isDealer = isDealer
        self.seatWind = seatWind
        self.isPlaying = isPlaying
        self.onRiichi = onRiichi
        self.onCorrect = onCorrect
        _correctedScore = State(initialValue: player.score)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        TileCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(seatWind) · \(player.name)\(isDealer ? "（親）" : "")")
                                        .font(.headline)
                                        .foregroundStyle(Theme.ink)
                                    Text("現在 \(player.score) 点")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.subInk)
                                }
                                Spacer()
                                Text("\(player.score)")
                                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        riichiButton
                        correctionCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle(player.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var riichiButton: some View {
        Button {
            onRiichi()
            dismiss()
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text(player.isRiichi ? "リーチを取り消す（1000点戻す）" : "リーチ宣言（1000点を供託）")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(player.isRiichi ? Color.gray : Theme.accent)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 3)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isPlaying || (!player.isRiichi && player.score < 1000))
        .opacity(!isPlaying || (!player.isRiichi && player.score < 1000) ? 0.5 : 1)
    }

    private var correctionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "点数修正", systemImage: "wrench.and.screwdriver")
            TileCard {
                VStack(spacing: 12) {
                    Text("\(correctedScore)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        Chip(title: "−1000", selected: false) { correctedScore -= 1000 }
                        Chip(title: "−100", selected: false) { correctedScore -= 100 }
                        Chip(title: "+100", selected: false) { correctedScore += 100 }
                        Chip(title: "+1000", selected: false) { correctedScore += 1000 }
                    }
                    if correctedScore != player.score {
                        Button {
                            onCorrect(correctedScore)
                            dismiss()
                        } label: {
                            Text("この点数に修正する")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background {
                                    RoundedRectangle(cornerRadius: 12).fill(Theme.green)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - あがり申告

struct WinFlowView: View {
    let game: LiveGameState
    /// 確定で精算を適用し，適用後の対局状態を返す（結果ステップの表示用）
    var onConfirm: (WinDeclaration) -> LiveGameState

    /// 開いた時点の対局状態のスナップショット．
    /// 確定後に親側の状態が次局へ進んでも，この画面の計算（本場・親判定）と
    /// 結果ステップの表示がずれないよう，参照は原則こちらを使う
    @State private var baseGame: LiveGameState

    @Environment(\.dismiss) private var dismiss
    @State private var winner: Int?
    @State private var method: WinMethod = .ron
    @State private var discarder: Int?
    @State private var han = 1
    @State private var fu = 30
    @State private var chiitoitsu = false
    @State private var yakuman = 0
    @State private var useTiles = true
    @State private var evaluation: HandEvaluation?
    @State private var handRiichi = false
    /// 精算適用後の状態．非nilの間は結果ステップを表示する
    @State private var appliedGame: LiveGameState?
    /// 供託（リーチ）の記録．開いた時点の対局状態で初期化し，この画面で修正できる
    @State private var riichiPlayers: Set<Int>

    init(game: LiveGameState, onConfirm: @escaping (WinDeclaration) -> LiveGameState) {
        self.game = game
        self.onConfirm = onConfirm
        _baseGame = State(initialValue: game)
        _riichiPlayers = State(initialValue: Set(game.players.indices.filter { game.players[$0].isRiichi && game.isPlaying($0) }))
    }

    private let fuValues = [20, 30, 40, 50, 60, 70, 80, 90, 100, 110]

    private var activeHan: Int { useTiles ? (evaluation?.han ?? 0) : han }
    private var activeFu: Int { useTiles ? (evaluation?.fu ?? 30) : fu }
    private var activeChiitoitsu: Bool { useTiles ? (evaluation?.isChiitoitsu ?? false) : chiitoitsu }
    private var activeYakuman: Int { useTiles ? (evaluation?.yakumanCount ?? 0) : yakuman }

    private var seatWindIndex: Int {
        guard let winner else { return 0 }
        return (winner - baseGame.dealerIndex + baseGame.perRound) % baseGame.perRound
    }

    private var roundWindIndex: Int {
        min(baseGame.handNumber / baseGame.perRound, 1)
    }

    private var result: ScoreResult? {
        guard let winner else { return nil }
        if method == .ron && discarder == nil { return nil }
        if useTiles && evaluation == nil { return nil }
        return ScoreCalculator.calculate(ScoreInput(
            han: activeHan, fu: activeFu,
            isDealer: winner == baseGame.dealerIndex,
            winMethod: method,
            honba: baseGame.honba, riichiSticks: riichiPlayers.count,
            isChiitoitsu: activeChiitoitsu, yakumanCount: activeYakuman,
            playerCount: baseGame.playingCount))
    }

    private var breakdownText: String {
        guard let result, let winner else { return "" }
        var parts: [String] = []
        if method == .ron, let discarder, let payment = result.ronPayment {
            parts.append("\(baseGame.players[discarder].name) から \(payment) 点")
        } else if method == .tsumo {
            if winner == baseGame.dealerIndex, let each = result.tsumoDealerPayment {
                parts.append("全員から \(each) 点ずつ")
            } else if let dealerPay = result.tsumoDealerPayment, let childPay = result.tsumoChildPayment {
                parts.append(baseGame.playingCount == 3
                    ? "親 \(dealerPay) 点 / 子 \(childPay) 点"
                    : "親 \(dealerPay) 点 / 子 \(childPay) 点ずつ")
            }
        }
        if riichiPlayers.count > 0 {
            parts.append("供託 \(riichiPlayers.count * 1000) 点")
        }
        return parts.joined(separator: " ＋ ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                if let appliedGame {
                    resultStep(appliedGame)
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            winnerCard
                        methodCard
                        if method == .ron {
                            discarderCard
                        }
                        riichiCard
                        inputModeCard
                        if useTiles {
                            HandInputView(
                                evaluation: $evaluation,
                                isTsumo: method == .tsumo,
                                isSanma: baseGame.isSanmaRules,
                                seatWind: seatWindIndex % 4,
                                roundWind: roundWindIndex,
                                riichi: $handRiichi)
                        } else {
                            if yakuman > 0 {
                                yakumanCard
                            } else {
                                hanFuCard
                            }
                            yakumanPickerCard
                        }
                        if let result {
                            previewCard(result)
                        }
                        confirmButton
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("あがり")
            .toolbar {
                if appliedGame == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { dismiss() }
                    }
                }
            }
            .onChange(of: winner) { _, newValue in
                if let newValue {
                    handRiichi = riichiPlayers.contains(newValue)
                }
            }
            .onChange(of: riichiPlayers) { _, newValue in
                if let winner {
                    handRiichi = newValue.contains(winner)
                }
            }
        }
    }

    /// 画面下部の確定ボタン．押すと精算を適用して結果ステップへ進む
    private var confirmButton: some View {
        Button {
            guard let winner else { return }
            appliedGame = onConfirm(WinDeclaration(
                winner: winner, method: method, discarder: discarder,
                han: activeHan, fu: activeFu,
                chiitoitsu: activeChiitoitsu, yakuman: activeYakuman,
                riichiPlayers: riichiPlayers))
        } label: {
            Text("確定")
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.accent)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 3)
                }
        }
        .buttonStyle(.plain)
        .disabled(result == nil)
        .opacity(result == nil ? 0.5 : 1)
    }

    /// 供託（リーチ）の記録．タップで切り替え，確定時に点数へ反映される
    private var riichiCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "供託（リーチ）", systemImage: "rectangle.portrait.and.arrow.right")
            TileCard {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(baseGame.playingIndices, id: \.self) { index in
                            Chip(
                                title: "\(baseGame.seatWind(of: index)) \(baseGame.players[index].name)",
                                selected: riichiPlayers.contains(index),
                                accent: index == baseGame.dealerIndex ? Theme.accent : Theme.green
                            ) {
                                if riichiPlayers.contains(index) {
                                    riichiPlayers.remove(index)
                                } else {
                                    riichiPlayers.insert(index)
                                }
                            }
                        }
                    }
                    Text(riichiPlayers.isEmpty
                        ? "リーチした人を選んでください．供託（1人1,000点）は勝者に入ります．"
                        : "供託 \(riichiPlayers.count) 本（\(riichiPlayers.count * 1000) 点）が勝者に入ります．")
                        .font(.caption)
                        .foregroundStyle(Theme.subInk)
                }
            }
        }
    }

    /// 確定後に表示する結果ステップ（役・符・点数と次の局）
    private func resultStep(_ applied: LiveGameState) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                winSummaryCard
                nextHandCard(applied)
                Button {
                    dismiss()
                } label: {
                    Text(applied.isFinished ? "閉じる" : "次の局へ")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.accent)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 3)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    private var winSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "あがり", systemImage: "checkmark.circle")
            TileCard {
                VStack(alignment: .leading, spacing: 12) {
                    if let winner {
                        HStack(spacing: 8) {
                            Text(baseGame.seatWind(of: winner))
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background {
                                    Circle().fill(winner == baseGame.dealerIndex ? Theme.accent : Theme.green)
                                }
                            Text(baseGame.players[winner].name)
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Text(winner == baseGame.dealerIndex ? "親" : "子")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.subInk)
                            Spacer()
                            Text(method == .ron ? "ロン" : "ツモ")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    if useTiles, let evaluation {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(evaluation.yaku.enumerated()), id: \.offset) { _, yaku in
                                HStack {
                                    Text(yaku.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
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
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(totalText(evaluation))
                                    .font(.headline)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    } else {
                        HStack {
                            Text("合計")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(manualTotalText)
                                .font(.headline)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    if !riichiPlayers.isEmpty {
                        Text("供託：\(riichiPlayers.sorted().map { baseGame.players[$0].name }.joined(separator: "，"))（\(riichiPlayers.count) 本）")
                            .font(.caption)
                            .foregroundStyle(Theme.subInk)
                    }
                    if let result {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            if !breakdownText.isEmpty {
                                Text(breakdownText)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.subInk)
                            }
                            HStack {
                                Text("受取合計")
                                    .font(.headline)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(result.totalReceived) 点")
                                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
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

    private var manualTotalText: String {
        if yakuman > 0 {
            return yakuman == 1 ? "役満" : "\(yakuman)倍役満"
        }
        return "\(han) 翻 \(fu) 符"
    }

    private func nextHandCard(_ applied: LiveGameState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "次の局", systemImage: "arrow.right.circle")
            TileCard {
                VStack(alignment: .leading, spacing: 8) {
                    if applied.isFinished {
                        Text("対局終了")
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(Theme.ink)
                        Text("対局画面の「結果」から，プレイヤーごとに成績へ保存できます．")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subInk)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(applied.roundLabel)
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Text("\(applied.honba) 本場")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.subInk)
                            if let winner, winner == baseGame.dealerIndex {
                                Text("連荘")
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background { Capsule().fill(Theme.accent) }
                            }
                        }
                        Text("親：\(applied.players[applied.dealerIndex].name)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subInk)
                    }
                    if let winner {
                        Divider()
                        HStack {
                            Text("\(baseGame.players[winner].name) の点数")
                                .font(.subheadline)
                                .foregroundStyle(Theme.subInk)
                            Spacer()
                            Text("\(applied.players[winner].score) 点")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
        }
    }

    private var inputModeCard: some View {
        HStack(spacing: 12) {
            BigToggle(title: "牌から入力", subtitle: "役・符を自動判定", selected: useTiles, accent: Theme.green) {
                useTiles = true
            }
            BigToggle(title: "翻・符で入力", subtitle: "自分で数える", selected: !useTiles, accent: Theme.green) {
                useTiles = false
            }
        }
    }

    private func playerChips(selected: Int?, exclude: Int?, action: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(baseGame.playingIndices, id: \.self) { index in
                if index != exclude {
                    Chip(
                        title: "\(baseGame.seatWind(of: index)) \(baseGame.players[index].name)",
                        selected: selected == index,
                        accent: index == baseGame.dealerIndex ? Theme.accent : Theme.green
                    ) {
                        action(index)
                    }
                }
            }
        }
    }

    private var winnerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "誰があがった？", systemImage: "person")
            TileCard {
                playerChips(selected: winner, exclude: nil) { index in
                    winner = index
                    if discarder == index { discarder = nil }
                }
            }
        }
    }

    private var methodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "あがり方", systemImage: "arrow.up.circle")
            HStack(spacing: 12) {
                BigToggle(title: "ロン", subtitle: "放銃者から全額", selected: method == .ron, accent: Theme.accent) {
                    method = .ron
                }
                BigToggle(title: "ツモ", subtitle: "全員から徴収", selected: method == .tsumo, accent: Theme.green) {
                    method = .tsumo
                    discarder = nil
                }
            }
        }
    }

    private var discarderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "誰から？", systemImage: "target")
            TileCard {
                playerChips(selected: discarder, exclude: winner) { discarder = $0 }
            }
        }
    }

    private var hanFuCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "翻と符", systemImage: "square.grid.3x3")
            TileCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("翻数（役＋ドラの合計）")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.subInk)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(1...13, id: \.self) { value in
                            Chip(title: "\(value)", selected: han == value) { han = value }
                        }
                    }
                    if !chiitoitsu {
                        Text("符")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.subInk)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(fuValues, id: \.self) { value in
                                Chip(title: "\(value)", selected: fu == value,
                                     accent: Theme.fuPalette[(fuValues.firstIndex(of: value) ?? 0) % Theme.fuPalette.count]) { fu = value }
                            }
                        }
                    }
                    Chip(title: "七対子 25符", selected: chiitoitsu, accent: Theme.gold) {
                        chiitoitsu.toggle()
                    }
                }
            }
        }
    }

    private var yakumanCard: some View {
        TileCard {
            HStack {
                Text("牌")
                Spacer()
                Text(yakuman == 1 ? "役満" : "\(yakuman)倍役満")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var yakumanPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "役満", systemImage: "crown")
            HStack(spacing: 8) {
                Chip(title: "なし", selected: yakuman == 0) { yakuman = 0 }
                Chip(title: "役満", selected: yakuman == 1, accent: Theme.accent) { yakuman = 1 }
                Chip(title: "ダブル", selected: yakuman == 2, accent: Theme.accent) { yakuman = 2 }
                Chip(title: "トリプル", selected: yakuman == 3, accent: Theme.accent) { yakuman = 3 }
            }
        }
    }

    private func previewCard(_ result: ScoreResult) -> some View {
        TileCard {
            VStack(spacing: 6) {
                if !result.rankName.isEmpty {
                    Text(result.rankName)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(LinearGradient(
                                colors: [Theme.gold, Theme.accent],
                                startPoint: .leading, endPoint: .trailing))
                        }
                }
                Text(result.displayText)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(breakdownText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.subInk)
                Text("受取合計 \(result.totalReceived) 点")
                    .font(.headline)
                    .foregroundStyle(Theme.green)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 流局申告

struct DrawFlowView: View {
    let game: LiveGameState
    /// 確定で精算を適用し，適用後の対局状態を返す（結果ステップの表示用）
    var onConfirm: (Set<Int>, Int?) -> LiveGameState

    /// 開いた時点の対局状態のスナップショット（WinFlowViewと同じ理由で保持する）
    @State private var baseGame: LiveGameState

    @Environment(\.dismiss) private var dismiss
    @State private var tenpai: Set<Int> = []
    @State private var nagashiWinner: Int?
    /// 精算適用後の状態．非nilの間は結果ステップを表示する
    @State private var appliedGame: LiveGameState?

    init(game: LiveGameState, onConfirm: @escaping (Set<Int>, Int?) -> LiveGameState) {
        self.game = game
        self.onConfirm = onConfirm
        _baseGame = State(initialValue: game)
    }

    private var previewText: String {
        if let nagashiWinner {
            let name = baseGame.players[nagashiWinner].name
            if nagashiWinner == baseGame.dealerIndex {
                return "\(name) の流し満貫：全員から 4,000 点ずつ（本場は1人 +100 点）．"
            }
            return "\(name) の流し満貫：親 4,000 点／子 2,000 点（本場は1人 +100 点）．"
        }
        let count = baseGame.playingCount
        if tenpai.count == 0 || tenpai.count == count {
            return "全員ノーテン（または全員テンパイ）のため，点数移動はありません．"
        }
        let gain = 3000 / tenpai.count
        let loss = 3000 / (count - tenpai.count)
        return "テンパイ\(tenpai.count)人：各+\(gain)点，ノーテン\(count - tenpai.count)人：各−\(loss)点"
    }

    private var continuityText: String {
        if let nagashiWinner {
            return nagashiWinner == baseGame.dealerIndex
                ? "流し満貫したのが親のため連荘します．本場は+1されます．"
                : "流し満貫したのが子のため親が流れます．本場は+1されます．"
        }
        return tenpai.contains(baseGame.dealerIndex)
            ? "親がテンパイのため連荘します．本場は+1されます．"
            : "親がノーテンのため親が流れます．本場は+1されます．"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                if let appliedGame {
                    resultStep(appliedGame)
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                FeltLabel(title: "テンパイは誰？", systemImage: "ear")
                            TileCard {
                                VStack(spacing: 8) {
                                    ForEach(baseGame.playingIndices, id: \.self) { index in
                                        Chip(
                                            title: "\(baseGame.seatWind(of: index)) \(baseGame.players[index].name)",
                                            selected: tenpai.contains(index),
                                            accent: index == baseGame.dealerIndex ? Theme.accent : Theme.green
                                        ) {
                                            if tenpai.contains(index) {
                                                tenpai.remove(index)
                                            } else {
                                                tenpai.insert(index)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            FeltLabel(title: "流し満貫", systemImage: "wind")
                            TileCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Chip(title: "なし", selected: nagashiWinner == nil, accent: Theme.gold) {
                                        nagashiWinner = nil
                                    }
                                    ForEach(baseGame.playingIndices, id: \.self) { index in
                                        Chip(
                                            title: "\(baseGame.seatWind(of: index)) \(baseGame.players[index].name)",
                                            selected: nagashiWinner == index,
                                            accent: Theme.gold
                                        ) {
                                            nagashiWinner = index
                                        }
                                    }
                                    Text("捨て牌が全部ヤオチュウ牌で誰にも鳴かれていない人が対象．選ぶとテンパイ料の精算はしません．")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.subInk)
                                }
                            }
                        }
                        TileCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(previewText)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(continuityText)
                                    .font(.caption)
                                    .foregroundStyle(Theme.subInk)
                                Text("供託リーチ棒は次局に持ち越されます．")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subInk)
                            }
                        }
                        confirmButton
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("流局")
            .toolbar {
                if appliedGame == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { dismiss() }
                    }
                }
            }
        }
    }

    /// 画面下部の確定ボタン．押すと精算を適用して結果ステップへ進む
    private var confirmButton: some View {
        Button {
            appliedGame = onConfirm(tenpai, nagashiWinner)
        } label: {
            Text("確定")
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.accent)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 3)
                }
        }
        .buttonStyle(.plain)
    }

    /// 確定後に表示する結果ステップ（精算内容と次の局）
    private func resultStep(_ applied: LiveGameState) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    FeltLabel(title: "流局", systemImage: "wind")
                    TileCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(previewText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(continuityText)
                                .font(.caption)
                                .foregroundStyle(Theme.subInk)
                            Text("供託リーチ棒は次局に持ち越されます．")
                                .font(.caption)
                                .foregroundStyle(Theme.subInk)
                        }
                    }
                }
                nextHandCard(applied)
                Button {
                    dismiss()
                } label: {
                    Text(applied.isFinished ? "閉じる" : "次の局へ")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.accent)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 3)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    private func nextHandCard(_ applied: LiveGameState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "次の局", systemImage: "arrow.right.circle")
            TileCard {
                VStack(alignment: .leading, spacing: 8) {
                    if applied.isFinished {
                        Text("対局終了")
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(Theme.ink)
                        Text("対局画面の「結果」から，プレイヤーごとに成績へ保存できます．")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subInk)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(applied.roundLabel)
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Text("\(applied.honba) 本場")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.subInk)
                            if applied.dealerIndex == baseGame.dealerIndex {
                                Text("連荘")
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background { Capsule().fill(Theme.accent) }
                            }
                        }
                        Text("親：\(applied.players[applied.dealerIndex].name)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subInk)
                    }
                }
            }
        }
    }
}

// MARK: - 結果

struct GameResultsView: View {
    let game: LiveGameState
    var onContinue: () -> Void
    var onReset: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var savedIndices: Set<Int> = []
    @State private var confirmingReset = false

    private struct StandingRow: Identifiable {
        let index: Int
        let rank: Int
        var id: Int { index }
    }

    /// スコア順（同点は席順）の順位表
    private var standings: [StandingRow] {
        let sorted = game.players.indices.sorted {
            game.players[$0].score != game.players[$1].score
                ? game.players[$0].score > game.players[$1].score
                : $0 < $1
        }
        return sorted.enumerated().map { StandingRow(index: $0.element, rank: $0.offset + 1) }
    }

    /// ウマの表示ラベル（4人打ちは「2位-1位」，3人打ちは「1位-0-1位」）
    private var umaLabel: String {
        if game.umaFirst == 0 && game.umaSecond == 0 { return "なし" }
        return game.players.count == 3
            ? "\(game.umaFirst)-0-\(game.umaFirst)"
            : "\(game.umaSecond)-\(game.umaFirst)"
    }

    /// pt換算．返し点・ウマ・オカは対局設定の値を使う．
    /// 5人以上の多人数打ちはウマ・オカなしで素点のみ
    private func points(rank: Int, score: Int) -> Double {
        if game.players.count > 4 {
            return Double(score - game.startScore) / 1000.0
        }
        let uma: Double = game.players.count == 3
            ? [Double(game.umaFirst), 0.0, -Double(game.umaFirst)][rank - 1]
            : [Double(game.umaFirst), Double(game.umaSecond),
               -Double(game.umaSecond), -Double(game.umaFirst)][rank - 1]
        let oka = game.okaEnabled && rank == 1
            ? Double((game.returnScore - game.startScore) * game.players.count) / 1000.0
            : 0
        return Double(score - game.returnScore) / 1000.0 + uma + oka
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        TileCard {
                            VStack(spacing: 10) {
                                ForEach(standings) { entry in
                                    let player = game.players[entry.index]
                                    HStack(spacing: 12) {
                                        Text("\(entry.rank)")
                                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                                            .foregroundStyle(.white)
                                            .frame(width: 38, height: 38)
                                            .background {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(RecordsView.rankColor(rank: entry.rank))
                                            }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(player.name)
                                                .font(.headline)
                                                .foregroundStyle(Theme.ink)
                                            Text("素点 \(player.score - game.startScore >= 0 ? "+" : "")\(player.score - game.startScore)")
                                                .font(.caption)
                                                .foregroundStyle(Theme.subInk)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text("\(player.score)")
                                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                                .foregroundStyle(Theme.ink)
                                            let pt = points(rank: entry.rank, score: player.score)
                                            Text("\(pt >= 0 ? "+" : "")\(String(format: "%.1f", pt)) pt")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(pt >= 0 ? Theme.green : Theme.accent)
                                        }
                                        Button {
                                            modelContext.insert(GameRecord(
                                                date: .now,
                                                rank: entry.rank,
                                                finalScore: player.score,
                                                gameType: game.gameType,
                                                memo: "\(player.name)（対局モード）",
                                                startingScore: game.startScore))
                                            savedIndices.insert(entry.index)
                                        } label: {
                                            Text(savedIndices.contains(entry.index) ? "保存済" : "保存")
                                                .font(.caption.weight(.heavy))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 5)
                                                .background {
                                                    Capsule().fill(savedIndices.contains(entry.index) ? Color.gray : Theme.green)
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(savedIndices.contains(entry.index))
                                    }
                                    if entry.rank < game.players.count { Divider() }
                                }
                            }
                        }
                        Text(game.players.count > 4
                            ? "pt換算：素点のみ（多人数打ちのためウマ・オカなし）"
                            : "pt換算：\(game.returnScore)点返し・ウマ\(umaLabel)\(game.okaEnabled && game.returnScore > game.startScore ? "・オカあり" : "")")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                        Button {
                            onContinue()
                            dismiss()
                        } label: {
                            Text("対局を続ける（延長）")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.black.opacity(0.35))
                                }
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            confirmingReset = true
                        } label: {
                            Text("対局を終了して破棄")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("結果")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .confirmationDialog("この対局を破棄しますか？", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("破棄する", role: .destructive) {
                    onReset()
                    dismiss()
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }
}
