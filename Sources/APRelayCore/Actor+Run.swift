extension Actor {
    /// Executes `body` on this actor's executor and returns the result.
    ///
    /// Works like `@MainActor.run { }` but for any actor instance.
    @inlinable
    package func run<T: Sendable, E: Error>(
        body: @Sendable (isolated Self) throws(E) -> T
    ) async throws(E) -> T {
        try body(self)
    }
}
