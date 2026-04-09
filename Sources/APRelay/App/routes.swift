import Prometheus
import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: IndexController())
    try app.register(collection: ActorController())
    try app.register(collection: InboxController())
    try app.register(collection: WebFingerController())
    try app.register(collection: NodeInfoController())
    try app.register(collection: AdminAPIController())

    // Prometheus metrics endpoint.
    app.get("metrics") { req -> String in
        req.application.prometheusRegistry?.emitToString() ?? ""
    }
}
