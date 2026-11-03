import XCTest
@testable import MahjongScore

final class ScoreCalculatorTests: XCTestCase {
    private func ron(han: Int, fu: Int, dealer: Bool = false) -> Int {
        ScoreCalculator.calculate(
            ScoreInput(han: han, fu: fu, isDealer: dealer, winMethod: .ron)
        ).ronPayment!
    }

    private func tsumo(han: Int, fu: Int, dealer: Bool = false) -> String {
        ScoreCalculator.calculate(
            ScoreInput(han: han, fu: fu, isDealer: dealer, winMethod: .tsumo)
        ).displayText
    }

    // MARK: - 子のロン

    func testChildRon() {
        XCTAssertEqual(ron(han: 1, fu: 30), 1000)
        XCTAssertEqual(ron(han: 1, fu: 40), 1300)
        XCTAssertEqual(ron(han: 2, fu: 30), 2000)
        XCTAssertEqual(ron(han: 3, fu: 30), 3900)
        XCTAssertEqual(ron(han: 3, fu: 60), 7700)
        XCTAssertEqual(ron(han: 4, fu: 30), 7700)
        XCTAssertEqual(ron(han: 4, fu: 40), 8000) // 満貫切り上げ
    }

    // MARK: - 親のロン

    func testDealerRon() {
        XCTAssertEqual(ron(han: 1, fu: 30, dealer: true), 1500)
        XCTAssertEqual(ron(han: 2, fu: 30, dealer: true), 2900)
        XCTAssertEqual(ron(han: 3, fu: 30, dealer: true), 5800)
        XCTAssertEqual(ron(han: 4, fu: 30, dealer: true), 11600)
        XCTAssertEqual(ron(han: 5, fu: 30, dealer: true), 12000)
    }

    // MARK: - ツモ

    func testTsumo() {
        // 子ツモの表記は「子の支払い / 親の支払い」
        XCTAssertEqual(tsumo(han: 1, fu: 30), "300 / 500")
        XCTAssertEqual(tsumo(han: 2, fu: 30), "500 / 1000")
        XCTAssertEqual(tsumo(han: 3, fu: 30), "1000 / 2000")
        XCTAssertEqual(tsumo(han: 1, fu: 30, dealer: true), "500オール")
        XCTAssertEqual(tsumo(han: 3, fu: 30, dealer: true), "2000オール")
        XCTAssertEqual(tsumo(han: 5, fu: 30), "2000 / 4000")
        XCTAssertEqual(tsumo(han: 5, fu: 30, dealer: true), "4000オール")
    }

    // MARK: - 満貫以上

    func testLimits() {
        XCTAssertEqual(ron(han: 5, fu: 30), 8000)          // 満貫
        XCTAssertEqual(ron(han: 6, fu: 30), 12000)         // 跳満
        XCTAssertEqual(ron(han: 8, fu: 30), 16000)         // 倍満
        XCTAssertEqual(ron(han: 11, fu: 30), 24000)        // 三倍満
        XCTAssertEqual(ron(han: 13, fu: 30), 32000)        // 数え役満
        XCTAssertEqual(ron(han: 5, fu: 30, dealer: true), 12000)
        XCTAssertEqual(ron(han: 6, fu: 30, dealer: true), 18000)
        XCTAssertEqual(ron(han: 13, fu: 30, dealer: true), 48000)
    }

    func testYakumanCount() {
        let double = ScoreCalculator.calculate(
            ScoreInput(winMethod: .ron, yakumanCount: 2))
        XCTAssertEqual(double.ronPayment, 64000)
        XCTAssertEqual(double.rankName, "2倍役満")
    }

    // MARK: - 七対子・平和ツモ

    func testChiitoitsu() {
        // 七対子2翻25符 = 子ロン1600
        let result = ScoreCalculator.calculate(
            ScoreInput(han: 2, fu: 30, winMethod: .ron, isChiitoitsu: true))
        XCTAssertEqual(result.ronPayment, 1600)
    }

    func testPinfuTsumo() {
        // 平和ツモ2翻20符 = 子400 / 親700
        XCTAssertEqual(tsumo(han: 2, fu: 20), "400 / 700")
    }

    // MARK: - 本場・供託

    func testHonba() {
        let ron = ScoreCalculator.calculate(
            ScoreInput(han: 1, fu: 30, winMethod: .ron, honba: 2))
        XCTAssertEqual(ron.ronPayment, 1000 + 600)

        let tsumo = ScoreCalculator.calculate(
            ScoreInput(han: 1, fu: 30, winMethod: .tsumo, honba: 1))
        XCTAssertEqual(tsumo.tsumoDealerPayment, 500 + 100)
        XCTAssertEqual(tsumo.tsumoChildPayment, 300 + 100)
    }

    func testRiichiSticks() {
        let result = ScoreCalculator.calculate(
            ScoreInput(han: 1, fu: 30, winMethod: .ron, riichiSticks: 2))
        XCTAssertEqual(result.ronPayment, 1000)      // 支払い自体は変わらない
        XCTAssertEqual(result.totalReceived, 3000)   // 供託2本分が加わる
    }
}

final class FuCalculatorTests: XCTestCase {
    func testMenzenRonBasic() {
        // 底符20 + 門前ロン10 = 30符
        var fu = FuCalculator()
        fu.winMethod = .ron
        XCTAssertEqual(fu.totalFu, 30)
    }

    func testOpenRonNoFu() {
        // 副露ロン，平和形相当は20符→30符扱い
        var fu = FuCalculator()
        fu.isClosedHand = false
        fu.winMethod = .ron
        XCTAssertEqual(fu.totalFu, 30)
    }

    func testTsumoWithSets() {
        // 底符20 + ツモ2 + 暗刻（么九）8 + 単騎2 = 32 → 40符
        var fu = FuCalculator()
        fu.winMethod = .tsumo
        fu.wait = .tanki
        fu.sets = [.ankouTerminal]
        XCTAssertEqual(fu.totalFu, 40)
    }

    func testChiitoitsu() {
        var fu = FuCalculator()
        fu.isChiitoitsu = true
        XCTAssertEqual(fu.totalFu, 25)
    }

    func testPinfuTsumo() {
        var fu = FuCalculator()
        fu.isPinfuTsumo = true
        XCTAssertEqual(fu.totalFu, 20)
    }

    // MARK: - 三人打ち（ツモ損あり）

    func testSanmaDealerTsumo() {
        // 親2翻30符ツモ: 1,000オールだが支払うのは2人だけ
        let r = ScoreCalculator.calculate(
            ScoreInput(han: 2, fu: 30, isDealer: true, winMethod: .tsumo, playerCount: 3))
        XCTAssertEqual(r.displayText, "1000オール")
        XCTAssertEqual(r.totalReceived, 2000)
    }

    func testSanmaChildTsumo() {
        // 子2翻30符ツモ: 500/1,000，子からは1人分だけ
        let r = ScoreCalculator.calculate(
            ScoreInput(han: 2, fu: 30, winMethod: .tsumo, playerCount: 3))
        XCTAssertEqual(r.displayText, "500 / 1000")
        XCTAssertEqual(r.totalReceived, 1500)
    }

    func testSanmaRonUnchanged() {
        // ロンは人数に依らない（子3翻30符 = 3,900）
        let r = ScoreCalculator.calculate(
            ScoreInput(han: 3, fu: 30, winMethod: .ron, playerCount: 3))
        XCTAssertEqual(r.totalReceived, 3900)
    }

    func testSanmaManganTsumo() {
        // 親満貫ツモ: 4,000オール × 2人 = 8,000
        let dealer = ScoreCalculator.calculate(
            ScoreInput(han: 5, fu: 30, isDealer: true, winMethod: .tsumo, playerCount: 3))
        XCTAssertEqual(dealer.totalReceived, 8000)
        // 子満貫ツモ: 2,000/4,000 → 6,000
        let child = ScoreCalculator.calculate(
            ScoreInput(han: 5, fu: 30, winMethod: .tsumo, playerCount: 3))
        XCTAssertEqual(child.totalReceived, 6000)
    }

    func testFourPlayerTsumoUnchanged() {
        // 四人打ちの従来計算が壊れていないこと
        let r = ScoreCalculator.calculate(
            ScoreInput(han: 2, fu: 30, isDealer: true, winMethod: .tsumo))
        XCTAssertEqual(r.totalReceived, 3000)
    }

    // MARK: - 多人数打ち（5人以上，ツモ全員払い）

    func testFivePlayerDealerTsumo() {
        // 親2翻30符ツモ: 1,000オール × 4人 = 4,000
        let r = ScoreCalculator.calculate(
            ScoreInput(han: 2, fu: 30, isDealer: true, winMethod: .tsumo, playerCount: 5))
        XCTAssertEqual(r.displayText, "1000オール")
        XCTAssertEqual(r.totalReceived, 4000)
    }

    func testFivePlayerChildTsumo() {
        // 子2翻30符ツモ: 親1,000 + 子500 × 3人 = 2,500
        let r = ScoreCalculator.calculate(
            ScoreInput(han: 2, fu: 30, winMethod: .tsumo, playerCount: 5))
        XCTAssertEqual(r.totalReceived, 2500)
    }

    func testSixPlayerManganTsumo() {
        // 親満貫ツモ: 4,000オール × 5人 = 20,000
        let r = ScoreCalculator.calculate(
            ScoreInput(han: 5, fu: 30, isDealer: true, winMethod: .tsumo, playerCount: 6))
        XCTAssertEqual(r.totalReceived, 20000)
    }
}
