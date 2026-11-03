import SwiftData
import SwiftUI

// MARK: - 対局記録モデル
//
// iCloud（CloudKit）同期へ移行できるよう，全プロパティにデフォルト値を
// 持たせ，一意制約は付けない．同期を有効化するときは Developer Program
// 加入のうえ iCloud capability を追加し，MahjonApp の ModelContainer を
// CloudKit 構成（.private("iCloud.com.deko.mahjon")）に切り替える．

@Model
final class GameRecord {
    var date: Date = Date.now
    /// 順位 1...4
    var rank: Int = 1
    /// 最終持ち点
    var finalScore: Int = 25000
    /// "東風" / "半荘"
    var gameType: String = "半荘"
    var memo: String = ""
    /// 開始持ち点（通常25000）
    var startingScore: Int = 25000

    init(date: Date = .now, rank: Int = 1, finalScore: Int = 25000,
         gameType: String = "半荘", memo: String = "", startingScore: Int = 25000) {
        self.date = date
        self.rank = rank
        self.finalScore = finalScore
        self.gameType = gameType
        self.memo = memo
        self.startingScore = startingScore
    }

    /// 素点収支（最終持ち点 − 開始持ち点．ウマ・オカは含まない）
    var pointDiff: Int { finalScore - startingScore }
}

// MARK: - 成績タブ

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GameRecord.date, order: .reverse) private var records: [GameRecord]
    @State private var addingNew = false
    @State private var editing: GameRecord?

    private var averageRank: Double {
        records.isEmpty ? 0 : Double(records.reduce(0) { $0 + $1.rank }) / Double(records.count)
    }

    private var averageScore: Int {
        records.isEmpty ? 0 : records.reduce(0) { $0 + $1.finalScore } / records.count
    }

    private func count(rank: Int) -> Int { records.filter { $0.rank == rank }.count }

    private func rate(rank: Int) -> Double {
        records.isEmpty ? 0 : Double(count(rank: rank)) / Double(records.count)
    }

    static let rankColors: [Color] = [Theme.accent, Theme.green, Theme.gold, Color.gray]

    /// 5位以下はグレーに寄せる安全な順位色
    static func rankColor(rank: Int) -> Color {
        rankColors[min(max(rank - 1, 0), rankColors.count - 1)]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                if records.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("成績")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addingNew = true
                    } label: {
                        Label("記録を追加", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $addingNew) {
                RecordEditorView(record: nil)
            }
            .sheet(item: $editing) { record in
                RecordEditorView(record: record)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            TileCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("まだ記録がありません")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("対局が終わったら順位と最終持ち点を記録．平均順位やトップ率などの成績がここに貯まります．データは端末内に保存され，将来はiCloudで同期できます．")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subInk)
                }
            }
            Button {
                addingNew = true
            } label: {
                Text("＋ 最初の記録を追加")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
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

    private var list: some View {
        List {
            statsRow
            ForEach(records) { record in
                recordRow(record)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
            .onDelete { offsets in
                for index in offsets {
                    modelContext.delete(records[index])
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: 統計カード

    private var statsRow: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    statTile(title: "対局数", value: "\(records.count)")
                    statTile(title: "平均順位", value: String(format: "%.2f", averageRank))
                    statTile(title: "トップ率", value: "\(Int(rate(rank: 1) * 100))%")
                    statTile(title: "ラス率", value: "\(Int(rate(rank: 4) * 100))%")
                }
                rankBar
                HStack {
                    ForEach(1...4, id: \.self) { rank in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Self.rankColors[rank - 1])
                                .frame(width: 9, height: 9)
                            Text("\(rank)位 \(count(rank: rank))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Divider()
                HStack {
                    Text("平均最終スコア")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subInk)
                    Spacer()
                    Text("\(averageScore)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.subInk)
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.chipOff)
        }
    }

    /// 順位分布の積み上げバー
    private var rankBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(1...4, id: \.self) { rank in
                    if count(rank: rank) > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Self.rankColors[rank - 1])
                            .frame(width: max(geo.size.width * rate(rank: rank) - 2, 4))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 16)
    }

    // MARK: 記録カード

    private func recordRow(_ record: GameRecord) -> some View {
        TileCard {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text("\(record.rank)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                    Text("位")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Self.rankColor(rank: record.rank))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 6) {
                        Text(record.gameType)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background { Capsule().fill(Theme.green) }
                        if !record.memo.isEmpty {
                            Text(record.memo)
                                .font(.caption)
                                .foregroundStyle(Theme.subInk)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(record.finalScore)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text(record.pointDiff >= 0 ? "+\(record.pointDiff)" : "\(record.pointDiff)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(record.pointDiff >= 0 ? Theme.green : Theme.accent)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editing = record
        }
    }
}

// MARK: - 記録エディタ

struct RecordEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let record: GameRecord?

    @State private var date: Date
    @State private var rank: Int
    @State private var finalScore: Int
    @State private var gameType: String
    @State private var memo: String

    init(record: GameRecord?) {
        self.record = record
        _date = State(initialValue: record?.date ?? .now)
        _rank = State(initialValue: record?.rank ?? 1)
        _finalScore = State(initialValue: record?.finalScore ?? 25000)
        _gameType = State(initialValue: record?.gameType ?? "半荘")
        _memo = State(initialValue: record?.memo ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        rankCard
                        scoreCard
                        detailCard
                        if record != nil {
                            deleteButton
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(record == nil ? "記録を追加" : "記録を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    private var rankCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "順位", systemImage: "trophy")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                ForEach(1...7, id: \.self) { value in
                    Chip(title: "\(value)位", selected: rank == value,
                         accent: RecordsView.rankColor(rank: value)) {
                        rank = value
                    }
                }
            }
        }
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "最終持ち点", systemImage: "100.square")
            TileCard {
                VStack(spacing: 12) {
                    TextField("最終持ち点", value: $finalScore, format: .number)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .numberPad()
                    HStack(spacing: 8) {
                        Chip(title: "−1000", selected: false) { finalScore -= 1000 }
                        Chip(title: "−100", selected: false) { finalScore -= 100 }
                        Chip(title: "+100", selected: false) { finalScore += 100 }
                        Chip(title: "+1000", selected: false) { finalScore += 1000 }
                    }
                    Text("開始 25000 点．収支は \(finalScore - 25000 >= 0 ? "+" : "")\(finalScore - 25000)")
                        .font(.caption)
                        .foregroundStyle(Theme.subInk)
                }
            }
        }
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeltLabel(title: "詳細", systemImage: "note.text")
            TileCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Chip(title: "東風", selected: gameType == "東風") { gameType = "東風" }
                        Chip(title: "半荘", selected: gameType == "半荘") { gameType = "半荘" }
                    }
                    DatePicker("日時", selection: $date)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    TextField("メモ（任意）", text: $memo)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if let record {
                modelContext.delete(record)
            }
            dismiss()
        } label: {
            Text("この記録を削除")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.accent)
                }
        }
        .buttonStyle(.plain)
    }

    private func save() {
        if let record {
            record.date = date
            record.rank = rank
            record.finalScore = finalScore
            record.gameType = gameType
            record.memo = memo
        } else {
            modelContext.insert(GameRecord(
                date: date, rank: rank, finalScore: finalScore,
                gameType: gameType, memo: memo))
        }
        dismiss()
    }
}

private extension View {
    /// iOSでは数字パッド，macOSでは何もしない
    @ViewBuilder func numberPad() -> some View {
        #if os(iOS)
            self.keyboardType(.numberPad)
        #else
            self
        #endif
    }
}
