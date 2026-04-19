import Queues

extension QueueName {
    /// The queue used for delivering activities to subscriber inboxes.
    static let delivery = QueueName(string: "delivery")

    /// The queue used for fetching remote instance info and heartbeat checks.
    static let instanceInfo = QueueName(string: "instanceInfo")
}
