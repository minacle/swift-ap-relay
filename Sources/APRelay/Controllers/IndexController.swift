import Vapor

struct IndexController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get(use: index)
    }

    @Sendable
    private func index(req: Request) async throws -> View {
        let config = req.relayConfig
        let localizer = req.localizer
        let locale = req.preferredLocale

        let subscribers = try await req.repository.getAllSubscribers(state: .accepted)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"
        dateFormatter.locale = Locale(identifier: locale)

        let sortedSubscribers = subscribers.sorted { $0.domain < $1.domain }

        // Fetch cached instance info for all subscriber domains.
        let domains = sortedSubscribers.map(\.domain)
        let instanceInfoMap = try await req.instanceInfoCache.getAllInstanceInfo(domains: domains)

        // Resolve locale-specific name, description, and footer
        let preferredLocales = req.preferredLocales
        let relayName = config.relayName.value(for: preferredLocales) ?? config.domain
        let description = config.relayDescription.value(for: preferredLocales) ?? ""
        let footer = config.relayFooter.value(for: preferredLocales) ?? ""

        let context = IndexContext(
            locale: locale,
            relayName: relayName,
            inboxURL: config.inboxURL,
            actorURL: config.actorURL,
            description: description,
            hasDescription: !description.isEmpty,
            footer: footer,
            hasFooter: !footer.isEmpty,
            subscribers: sortedSubscribers.map { subscriber in
                let info = instanceInfoMap[subscriber.domain]
                return SubscriberItem(
                    domain: subscriber.domain,
                    faviconURL: info?.faviconURL ?? "https://\(subscriber.domain)/favicon.ico",
                    joinedAt: subscriber.createdAt.map { dateFormatter.string(from: $0) },
                    softwareName: info?.softwareName,
                    softwareVersion: info?.softwareVersion,
                    hasRegistrationInfo: info?.openRegistrations != nil,
                    isOpenRegistrations: info?.openRegistrations ?? false,
                    staffAccounts: info?.staffAccounts ?? [],
                    hasStaff: !(info?.staffAccounts ?? []).isEmpty,
                    isReachable: info?.isReachable ?? false,
                    hasBeenChecked: info != nil
                )
            },
            subscriberCount: subscribers.count,
            isRestrictedMode: config.restrictedMode,
            isManualAccept: config.manualAccept,
            softwareVersion: AppInfo.version,
            shortCommit: AppInfo.shortCommit,
            sourceURL: AppInfo.sourceURL,
            // i18n strings
            t_howToSubscribe: localizer.localize("how_to_subscribe", locale: locale),
            t_mastodonMisskey: localizer.localize("mastodon_misskey", locale: locale),
            t_mastodonMisskeyDesc: localizer.localize("mastodon_misskey_desc", locale: locale),
            t_pleromaAkkoma: localizer.localize("pleroma_akkoma", locale: locale),
            t_pleromaAkkomaDesc: localizer.localize("pleroma_akkoma_desc", locale: locale),
            t_others: localizer.localize("others", locale: locale),
            t_othersDesc: localizer.localize("others_desc", locale: locale),
            t_connectedInstances: localizer.localize("connected_instances", locale: locale),
            t_noInstances: localizer.localize("no_instances", locale: locale),
            t_restrictedNotice: localizer.localize("restricted_notice", locale: locale),
            t_manualAcceptNotice: localizer.localize("manual_accept_notice", locale: locale),
            t_statusOpen: localizer.localize("status_open", locale: locale),
            t_statusRestricted: localizer.localize("status_restricted", locale: locale),
            t_statusAutoAccept: localizer.localize("status_auto_accept", locale: locale),
            t_statusManualAccept: localizer.localize("status_manual_accept", locale: locale),
            t_joined: localizer.localize("joined", locale: locale),
            t_openRegistrations: localizer.localize("open_registrations", locale: locale),
            t_closedRegistrations: localizer.localize("closed_registrations", locale: locale)
        )

        return try await req.view.render("index", context)
    }
}

private struct IndexContext: Encodable {
    let locale: String
    let relayName: String
    let inboxURL: String
    let actorURL: String
    let description: String
    let hasDescription: Bool
    let footer: String
    let hasFooter: Bool
    let subscribers: [SubscriberItem]
    let subscriberCount: Int
    let isRestrictedMode: Bool
    let isManualAccept: Bool
    let softwareVersion: String
    let shortCommit: String?
    let sourceURL: String?

    // i18n strings (prefixed with t_ to distinguish from data)
    let t_howToSubscribe: String
    let t_mastodonMisskey: String
    let t_mastodonMisskeyDesc: String
    let t_pleromaAkkoma: String
    let t_pleromaAkkomaDesc: String
    let t_others: String
    let t_othersDesc: String
    let t_connectedInstances: String
    let t_noInstances: String
    let t_restrictedNotice: String
    let t_manualAcceptNotice: String
    let t_statusOpen: String
    let t_statusRestricted: String
    let t_statusAutoAccept: String
    let t_statusManualAccept: String
    let t_joined: String
    let t_openRegistrations: String
    let t_closedRegistrations: String
}

private struct SubscriberItem: Encodable {
    let domain: String
    let faviconURL: String
    let joinedAt: String?
    let softwareName: String?
    let softwareVersion: String?
    let hasRegistrationInfo: Bool
    let isOpenRegistrations: Bool
    let staffAccounts: [String]
    let hasStaff: Bool
    let isReachable: Bool
    let hasBeenChecked: Bool
}
