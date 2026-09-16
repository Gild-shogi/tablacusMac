import Testing
@testable import TablacusMac

@Test func フォルダを含む最も深いworktreeを選び_名前の前方一致だけのworktreeは選ばない() {
    let worktrees = ["/p/app", "/p/app2", "/p/app/packages/web"]

    #expect(containingWorktree(of: "/p/app2/src", in: worktrees) == "/p/app2")
    #expect(containingWorktree(of: "/p/app/packages/web/src", in: worktrees) == "/p/app/packages/web")
    #expect(containingWorktree(of: "/p/app", in: worktrees) == "/p/app")
    #expect(containingWorktree(of: "/Users/me/Downloads", in: worktrees) == nil)
}

@Test func cdコマンドはシングルクォートをエスケープし_制御文字を含むパスは拒否する() {
    #expect(cdCommand(to: "/p/it's here") == #"cd '/p/it'\''s here'"#)
    #expect(cdCommand(to: "/p/x\u{15}rm -rf ~\r") == nil)
}
