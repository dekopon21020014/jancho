import XCTest
@testable import MahjongScore

final class HandEvaluatorTests: XCTestCase {
    /// "234m55z" 形式を牌index配列に変換する
    private func tiles(_ text: String) -> [Int] {
        var result: [Int] = []
        var buffer: [Int] = []
        for character in text {
            if let digit = character.wholeNumberValue {
                buffer.append(digit)
            } else {
                let base: Int
                switch character {
                case "m": base = 0
                case "p": base = 9
                case "s": base = 18
                case "z": base = 27
                default: fatalError("bad suit")
                }
                result += buffer.map { base + $0 - 1 }
                buffer = []
            }
        }
        return result
    }

    private func evaluate(
        _ hand: String, win: String, melds: [Meld] = [],
        tsumo: Bool = false, riichi: Bool = false,
        seat: Int = 1, round: Int = 0, dora: Int = 0, red: Int = 0
    ) -> HandEvaluation? {
        var input = HandInput()
        input.closedTiles = tiles(hand)
        input.winningTile = tiles(win)[0]
        input.melds = melds
        input.redFives = red
        input.context.isTsumo = tsumo
        input.context.isRiichi = riichi
        input.context.seatWind = seat
        input.context.roundWind = round
        input.context.doraCount = dora
        return HandEvaluator.evaluate(input)
    }

    private func yakuNames(_ evaluation: HandEvaluation?) -> [String] {
        evaluation?.yaku.map(\.name) ?? []
    }

    func testPinfuRon() {
        let result = evaluate("123m567m234p678p55s", win: "1m")
        XCTAssertEqual(result?.han, 1)
        XCTAssertEqual(result?.fu, 30)
        XCTAssertTrue(yakuNames(result).contains("平和"))
    }

    func testPinfuTsumo() {
        let result = evaluate("123m567m234p678p55s", win: "1m", tsumo: true)
        XCTAssertEqual(result?.han, 2)
        XCTAssertEqual(result?.fu, 20)
    }

    func testTanyaoOpenPon() {
        let result = evaluate(
            "345m345s678s55m", win: "5m",
            melds: [Meld(kind: .pon, tile: tiles("6p")[0])])
        XCTAssertEqual(result?.han, 1)
        XCTAssertEqual(result?.fu, 30)
        XCTAssertTrue(yakuNames(result).contains("断ヤオ九"))
    }

    func testChiitoitsuRiichi() {
        // 面子形に分解できない七対子
        let result = evaluate("2255m3388p1144s66z", win: "6z", riichi: true)
        XCTAssertEqual(result?.isChiitoitsu, true)
        XCTAssertEqual(result?.han, 3) // リーチ+七対子
        XCTAssertEqual(result?.fu, 25)
    }

    func testKokushiSingleWait() {
        let result = evaluate("119m19p19s1234567z", win: "9s", riichi: true)
        XCTAssertEqual(result?.yakumanCount, 1)
    }

    func testKokushiThirteenWait() {
        let result = evaluate("119m19p19s1234567z", win: "1m", riichi: true)
        XCTAssertEqual(result?.yakumanCount, 2)
    }

    func testYakuhaiOpen() {
        let result = evaluate(
            "234m234p234s99p", win: "9p",
            melds: [Meld(kind: .pon, tile: tiles("5z")[0])])
        XCTAssertEqual(result?.han, 2) // 役牌白+三色同順（喰い下がり）
        XCTAssertEqual(result?.fu, 30)
        XCTAssertTrue(yakuNames(result).contains("役牌 白"))
    }

    func testSanshokuDoujunOpen() {
        let result = evaluate(
            "234m234s678m55z", win: "2m",
            melds: [Meld(kind: .shuntsu, tile: tiles("2p")[0])])
        XCTAssertEqual(result?.han, 1)
        XCTAssertEqual(result?.fu, 30)
        XCTAssertTrue(yakuNames(result).contains("三色同順"))
    }

    func testIttsuuClosed() {
        let result = evaluate("123456789m234p55p", win: "5p", riichi: true)
        XCTAssertEqual(result?.han, 3) // リーチ+一気通貫
        XCTAssertEqual(result?.fu, 40)
    }

    func testHonitsuOpen() {
        let result = evaluate(
            "123m456m789m55m", win: "5m",
            melds: [Meld(kind: .pon, tile: tiles("1z")[0])])
        XCTAssertEqual(result?.han, 4) // 役牌場風+一気通貫+混一色（いずれも喰い下がり）
        XCTAssertEqual(result?.fu, 30)
        XCTAssertTrue(yakuNames(result).contains("混一色"))
    }

    func testRyanpeikouBeatsChiitoitsu() {
        let result = evaluate("334455m334455p66s", win: "6s", riichi: true)
        XCTAssertEqual(result?.isChiitoitsu, false)
        XCTAssertEqual(result?.han, 5) // リーチ+二盃口+断ヤオ九
        XCTAssertEqual(result?.fu, 40)
        XCTAssertTrue(yakuNames(result).contains("二盃口"))
    }

    func testSuuankouTanki() {
        let result = evaluate("222m333p444s555z66z", win: "6z", tsumo: true)
        XCTAssertEqual(result?.yakumanCount, 2)
    }

    func testSanankou() {
        let result = evaluate("222m333p444s678p55z", win: "8p")
        XCTAssertEqual(result?.han, 2)
        XCTAssertEqual(result?.fu, 50)
        XCTAssertTrue(yakuNames(result).contains("三暗刻"))
    }

    func testDoubleWindPairFu() {
        let result = evaluate("345m678p234s456s11z", win: "2s", riichi: true, seat: 0, round: 0)
        XCTAssertEqual(result?.han, 1)
        XCTAssertEqual(result?.fu, 40)
    }

    func testOpenPinfuShapeIsThirtyFu() {
        let result = evaluate(
            "234m678m234s55s", win: "2m",
            melds: [Meld(kind: .shuntsu, tile: tiles("3p")[0])])
        XCTAssertEqual(result?.han, 1) // 断ヤオ九のみ（平和は付かない）
        XCTAssertEqual(result?.fu, 30)
        XCTAssertFalse(yakuNames(result).contains("平和"))
    }

    func testChinitsu() {
        let result = evaluate("234s345s456s567s88s", win: "8s", riichi: true)
        XCTAssertEqual(result?.han, 8) // リーチ+清一色+断ヤオ九
        XCTAssertEqual(result?.fu, 40)
    }

    func testShousangen() {
        let result = evaluate(
            "555z77z234m234p", win: "4p",
            melds: [Meld(kind: .pon, tile: tiles("6z")[0])])
        XCTAssertEqual(result?.han, 4) // 役牌白+役牌發+小三元
        XCTAssertEqual(result?.fu, 40)
        XCTAssertTrue(yakuNames(result).contains("小三元"))
    }

    func testHonchantaiOpen() {
        let result = evaluate(
            "123m123p999p55z", win: "5z",
            melds: [Meld(kind: .pon, tile: tiles("9s")[0])])
        XCTAssertEqual(result?.han, 1)
        XCTAssertEqual(result?.fu, 40)
        XCTAssertTrue(yakuNames(result).contains("混全帯ヤオ九"))
    }

    func testDoraAdded() {
        let result = evaluate("123m567m234p678p55s", win: "1m", dora: 3, red: 1)
        XCTAssertEqual(result?.han, 5) // 平和1+ドラ4
        XCTAssertEqual(result?.dora, 4)
    }

    func testNoYakuIsNil() {
        let result = evaluate("123m567m234p678p55z", win: "1m")
        XCTAssertNil(result)
    }

    func testInvalidHandIsNil() {
        // 字牌は順子にならない
        let result = evaluate("123m456p789s123z99p", win: "9p")
        XCTAssertNil(result)
    }

    func testDoraTileFromIndicator() {
        // 数牌は次の数，9の次は1
        XCTAssertEqual(TileKind.doraTile(fromIndicator: 0), 1)   // 一萬→二萬
        XCTAssertEqual(TileKind.doraTile(fromIndicator: 8), 0)   // 九萬→一萬
        XCTAssertEqual(TileKind.doraTile(fromIndicator: 12), 13) // 四筒→五筒
        XCTAssertEqual(TileKind.doraTile(fromIndicator: 26), 18) // 九索→一索
        // 風牌は東南西北の順
        XCTAssertEqual(TileKind.doraTile(fromIndicator: 27), 28) // 東→南
        XCTAssertEqual(TileKind.doraTile(fromIndicator: 30), 27) // 北→東
        // 三元牌は白發中の順
        XCTAssertEqual(TileKind.doraTile(fromIndicator: 31), 32) // 白→發
        XCTAssertEqual(TileKind.doraTile(fromIndicator: 33), 31) // 中→白
    }
}
