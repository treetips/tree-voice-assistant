import Foundation

/// 保存要求の集約。連続した変更を1回の書き込みにまとめる。
@MainActor
final class SaveCoalescer {
    private var task: Task<Void, Never>?
    private var generation = 0

    /// 保存予約。連続した変更を1回の書き込みにまとめる。
    func schedule(delay: Duration = .milliseconds(300), work: @escaping @MainActor () -> Void) {
        generation += 1
        let gen = generation
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, gen == generation else { return }
            work()
        }
    }

    /// 予約を取り消して即時実行する。
    func flush(_ work: @MainActor () -> Void) {
        generation += 1
        task?.cancel()
        task = nil
        work()
    }
}
