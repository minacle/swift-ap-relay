import Queues

extension QueueName {
    /// The queue used for delivering activities to subscriber inboxes.
    static let delivery = QueueName(string: "delivery")
}
