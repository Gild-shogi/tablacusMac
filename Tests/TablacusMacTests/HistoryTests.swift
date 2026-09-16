import Foundation
import Testing
@testable import TablacusMac

@Test func 戻った後に別の場所へ移動すると進む履歴が消える() {
    let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b"), c = URL(fileURLWithPath: "/c")
    var history = History(a)

    history.visit(b)
    history.goBack()
    #expect(history.current == a)
    history.goForward()
    #expect(history.current == b)

    history.goBack()
    history.visit(c)
    #expect(history.current == c)
    #expect(history.back == [a])
    #expect(history.forward.isEmpty)
}
