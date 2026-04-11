import Vapor

struct AdminCommandGroup: AsyncCommandGroup {
    let help: String = "Manage the relay (subscribers and blocked domains)"

    let commands: [String: any AnyAsyncCommand] = [
        "accept": AcceptCommand(),
        "reject": RejectCommand(),
        "block": BlockCommand(),
        "unblock": UnblockCommand(),
        "list-subscribers": ListSubscribersCommand(),
        "list-blocked-domains": ListBlockedDomainsCommand(),
    ]
}
