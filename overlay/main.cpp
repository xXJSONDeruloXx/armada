#include <QDBusConnection>
#include <QDBusInterface>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QProcess>
#include <QRegularExpression>
#include <QRegion>
#include <QScreen>
#include <QSaveFile>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <xcb/xcb.h>

namespace {

struct RpcResult {
    bool ok = false;
    QJsonValue result;
    QString error;
};

struct GamescopeFocusState {
    xcb_window_t overlayWindow = XCB_WINDOW_NONE;
    xcb_window_t steamWindow = XCB_WINDOW_NONE;
    uint32_t steamOverlay = 0;
    uint32_t steamInputFocus = 0;
    uint32_t steamNotification = 0;
    bool saved = false;
};

GamescopeFocusState gamescopeFocusState;

QString discoverInputEventPath()
{
    const QString service = QStringLiteral("org.shadowblip.InputPlumber");
    const QString managerPath = QStringLiteral("/org/shadowblip/InputPlumber/Manager");
    const QString compositeInterface = QStringLiteral("org.shadowblip.Input.CompositeDevice");
    QDBusInterface manager(service, managerPath, QStringLiteral("org.shadowblip.InputManager"),
        QDBusConnection::systemBus());
    const QStringList composites = manager.property(QStringLiteral("GamepadOrder")).toStringList();
    for (const QString &composite : composites) {
        QDBusInterface device(service, composite, compositeInterface, QDBusConnection::systemBus());
        const QStringList targets = device.property(QStringLiteral("DbusDevices")).toStringList();
        for (const QString &target : targets)
            if (target.startsWith(QStringLiteral("/org/shadowblip/InputPlumber/devices/target/dbus")))
                return target;
    }
    return {};
}

QString overlayPreferencesFile()
{
    QString config = qEnvironmentVariable("XDG_CONFIG_HOME");
    if (config.isEmpty())
        config = QDir::homePath() + QStringLiteral("/.config");
    return QDir(config).filePath(QStringLiteral("armada/overlay.json"));
}

QVariantMap defaultOverlayPreferences()
{
    return {
        {QStringLiteral("layout"), QStringLiteral("centered")},
        {QStringLiteral("centeredChord"), QStringLiteral("start_select")},
        {QStringLiteral("sideChord"), QStringLiteral("start_select")},
        {QStringLiteral("swipeEnabled"), true},
        {QStringLiteral("swipeEdge"), QStringLiteral("left")},
        {QStringLiteral("swipeDistance"), 120},
    };
}

bool validOverlayPreferences(const QVariantMap &preferences);

QVariantMap loadOverlayPreferences()
{
    QVariantMap result = defaultOverlayPreferences();
    QFile file(overlayPreferencesFile());
    if (!file.open(QIODevice::ReadOnly))
        return result;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return result;
    const QVariantMap stored = document.object().toVariantMap();
    for (auto it = stored.cbegin(); it != stored.cend(); ++it)
        if (result.contains(it.key()))
            result.insert(it.key(), it.value());
    return validOverlayPreferences(result) ? result : defaultOverlayPreferences();
}

bool validOverlayPreferences(const QVariantMap &preferences)
{
    const QString layout = preferences.value(QStringLiteral("layout")).toString();
    const QString centeredChord = preferences.value(QStringLiteral("centeredChord")).toString();
    const QString sideChord = preferences.value(QStringLiteral("sideChord")).toString();
    const QString edge = preferences.value(QStringLiteral("swipeEdge")).toString();
    const QStringList layouts = {QStringLiteral("centered"), QStringLiteral("side")};
    const QStringList chords = {
        QStringLiteral("start_select"), QStringLiteral("guide"), QStringLiteral("quick_access"),
        QStringLiteral("select_l1"), QStringLiteral("select_r1"),
    };
    const QStringList edges = {QStringLiteral("left"), QStringLiteral("right"), QStringLiteral("bottom")};
    const int distance = preferences.value(QStringLiteral("swipeDistance")).toInt();
    return layouts.contains(layout) && chords.contains(centeredChord) && chords.contains(sideChord)
        && edges.contains(edge) && preferences.value(QStringLiteral("swipeEnabled")).typeId() == QMetaType::Bool
        && distance >= 48 && distance <= 320;
}

QString controlSocket()
{
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    return (runtime.isEmpty() ? QStringLiteral("/run/user/%1").arg(QString::number(getuid())) : runtime)
        + QStringLiteral("/armada-control-overlay/control.sock");
}

QString apiSocket()
{
    return qEnvironmentVariable("ARMADA_OVERLAY_SOCKET", "/run/armada/overlay.sock");
}

RpcResult request(const QString &action, const QJsonObject &fields = {})
{
    QLocalSocket socket;
    socket.connectToServer(apiSocket());
    if (!socket.waitForConnected(1500))
        return {false, {}, QStringLiteral("Armada service is unavailable")};
    QJsonObject payload = fields;
    payload.insert(QStringLiteral("action"), action);
    socket.write(QJsonDocument(payload).toJson(QJsonDocument::Compact) + '\n');
    if (!socket.waitForBytesWritten(500) || !socket.waitForReadyRead(5000))
        return {false, {}, QStringLiteral("Armada service did not respond")};
    const QJsonDocument response = QJsonDocument::fromJson(socket.readLine());
    if (!response.isObject())
        return {false, {}, QStringLiteral("Invalid Armada service response")};
    const QJsonObject object = response.object();
    if (!object.value(QStringLiteral("ok")).toBool())
        return {false, {}, object.value(QStringLiteral("error")).toString()};
    return {true, object.value(QStringLiteral("result")), {}};
}

bool sendCommand(const QString &command)
{
    QLocalSocket socket;
    socket.connectToServer(controlSocket());
    if (!socket.waitForConnected(200))
        return false;
    const QByteArray payload = command.toUtf8() + '\n';
    if (socket.write(payload) != payload.size())
        return false;
    socket.flush();
    socket.waitForBytesWritten(200);
    return true;
}

bool gamescopeRootHasProperty(const QString &displayName, const char *propertyName)
{
    const QByteArray displayBytes = displayName.toLocal8Bit();
    int screen = 0;
    xcb_connection_t *connection = xcb_connect(displayBytes.constData(), &screen);
    if (!connection || xcb_connection_has_error(connection)) {
        if (connection)
            xcb_disconnect(connection);
        return false;
    }
    const auto atomCookie = xcb_intern_atom(connection, 0,
        static_cast<uint16_t>(strlen(propertyName)), propertyName);
    xcb_intern_atom_reply_t *atomReply = xcb_intern_atom_reply(connection, atomCookie, nullptr);
    const xcb_atom_t property = atomReply ? atomReply->atom : static_cast<xcb_atom_t>(XCB_ATOM_NONE);
    free(atomReply);
    const xcb_screen_t *screenInfo = xcb_setup_roots_iterator(xcb_get_setup(connection)).data;
    bool present = false;
    if (property != XCB_ATOM_NONE && screenInfo) {
        const auto cookie = xcb_get_property(connection, 0, screenInfo->root, property,
            XCB_GET_PROPERTY_TYPE_ANY, 0, 1);
        xcb_get_property_reply_t *reply = xcb_get_property_reply(connection, cookie, nullptr);
        present = reply && reply->value_len > 0;
        free(reply);
    }
    xcb_disconnect(connection);
    return present;
}

QString discoverGamescopeDisplay()
{
    QString first;
    const QRegularExpression pattern(QStringLiteral("^X(\\d+)$"));
    const QStringList sockets = QDir(QStringLiteral("/tmp/.X11-unix"))
        .entryList(QDir::AllEntries | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &socket : sockets) {
        const QRegularExpressionMatch match = pattern.match(socket);
        if (!match.hasMatch())
            continue;
        const QString display = QStringLiteral(":") + match.captured(1);
        if (first.isEmpty())
            first = display;
        if (gamescopeRootHasProperty(display, "GAMESCOPE_FOCUSED_WINDOW"))
            return display;
    }
    return first;
}

QString gamescopeStateFile()
{
    return QFileInfo(controlSocket()).absolutePath() + QStringLiteral("/gamescope-focus.json");
}

void setCardinal(xcb_connection_t *connection, xcb_window_t window, xcb_atom_t property, uint32_t value)
{
    if (property != XCB_ATOM_NONE)
        xcb_change_property(connection, XCB_PROP_MODE_REPLACE, window, property,
            XCB_ATOM_CARDINAL, 32, 1, &value);
}

void setAtom(xcb_connection_t *connection, xcb_window_t window, xcb_atom_t property, xcb_atom_t value)
{
    if (property != XCB_ATOM_NONE && value != XCB_ATOM_NONE)
        xcb_change_property(connection, XCB_PROP_MODE_REPLACE, window, property,
            XCB_ATOM_ATOM, 32, 1, &value);
}

void syncXcb(xcb_connection_t *connection)
{
    xcb_flush(connection);
    const auto cookie = xcb_get_input_focus(connection);
    xcb_get_input_focus_reply_t *reply = xcb_get_input_focus_reply(connection, cookie, nullptr);
    free(reply);
}

xcb_window_t findSteamWindow(xcb_connection_t *connection, xcb_window_t root, xcb_atom_t wmClass)
{
    const auto cookie = xcb_query_tree(connection, root);
    xcb_query_tree_reply_t *tree = xcb_query_tree_reply(connection, cookie, nullptr);
    if (!tree)
        return XCB_WINDOW_NONE;
    const int length = xcb_query_tree_children_length(tree);
    const xcb_window_t *children = xcb_query_tree_children(tree);
    for (int index = 0; index < length; ++index) {
        const auto propertyCookie = xcb_get_property(connection, 0, children[index], wmClass,
            XCB_GET_PROPERTY_TYPE_ANY, 0, 32);
        xcb_get_property_reply_t *property = xcb_get_property_reply(connection, propertyCookie, nullptr);
        if (!property)
            continue;
        const QByteArray value(static_cast<const char *>(xcb_get_property_value(property)),
            xcb_get_property_value_length(property));
        free(property);
        if (value.contains("steamwebhelper") || value.contains("steam")) {
            const xcb_window_t result = children[index];
            free(tree);
            return result;
        }
    }
    free(tree);
    return XCB_WINDOW_NONE;
}

void saveGamescopeFocusState()
{
    QJsonObject state;
    state.insert(QStringLiteral("display"), qEnvironmentVariable("DISPLAY"));
    state.insert(QStringLiteral("overlayWindow"), static_cast<qint64>(gamescopeFocusState.overlayWindow));
    state.insert(QStringLiteral("steamWindow"), static_cast<qint64>(gamescopeFocusState.steamWindow));
    state.insert(QStringLiteral("steamOverlay"), static_cast<int>(gamescopeFocusState.steamOverlay));
    state.insert(QStringLiteral("steamInputFocus"), static_cast<int>(gamescopeFocusState.steamInputFocus));
    state.insert(QStringLiteral("steamNotification"), static_cast<int>(gamescopeFocusState.steamNotification));
    QFile file(gamescopeStateFile());
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        file.write(QJsonDocument(state).toJson(QJsonDocument::Compact));
}

bool loadGamescopeFocusState()
{
    QFile file(gamescopeStateFile());
    if (!file.open(QIODevice::ReadOnly))
        return false;
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return false;
    const QJsonObject state = document.object();
    gamescopeFocusState.overlayWindow = static_cast<xcb_window_t>(state.value(QStringLiteral("overlayWindow")).toInteger());
    gamescopeFocusState.steamWindow = static_cast<xcb_window_t>(state.value(QStringLiteral("steamWindow")).toInteger());
    gamescopeFocusState.steamOverlay = static_cast<uint32_t>(state.value(QStringLiteral("steamOverlay")).toInt());
    gamescopeFocusState.steamInputFocus = static_cast<uint32_t>(state.value(QStringLiteral("steamInputFocus")).toInt());
    gamescopeFocusState.steamNotification = static_cast<uint32_t>(state.value(QStringLiteral("steamNotification")).toInt());
    gamescopeFocusState.saved = true;
    return true;
}

void markGamescopeOverlay(WId window)
{
    gamescopeFocusState.overlayWindow = static_cast<xcb_window_t>(window);
    int screen = 0;
    xcb_connection_t *connection = xcb_connect(nullptr, &screen);
    if (!connection || xcb_connection_has_error(connection)) {
        if (connection)
            xcb_disconnect(connection);
        return;
    }
    const auto atom = [connection](const char *name) {
        const auto cookie = xcb_intern_atom(connection, 0, static_cast<uint16_t>(strlen(name)), name);
        xcb_intern_atom_reply_t *reply = xcb_intern_atom_reply(connection, cookie, nullptr);
        const xcb_atom_t value = reply ? reply->atom : static_cast<xcb_atom_t>(XCB_ATOM_NONE);
        free(reply);
        return value;
    };
    const xcb_atom_t overlay = atom("STEAM_OVERLAY");
    const xcb_atom_t inputFocus = atom("STEAM_INPUT_FOCUS");
    const xcb_atom_t notification = atom("STEAM_NOTIFICATION");
    const xcb_atom_t wmClass = atom("WM_CLASS");
    const xcb_atom_t windowType = atom("_NET_WM_WINDOW_TYPE");
    const xcb_atom_t dockType = atom("_NET_WM_WINDOW_TYPE_DOCK");
    if (!gamescopeFocusState.saved) {
        const xcb_screen_t *screenInfo = xcb_setup_roots_iterator(xcb_get_setup(connection)).data;
        gamescopeFocusState.steamWindow = screenInfo
            ? findSteamWindow(connection, screenInfo->root, wmClass)
            : static_cast<xcb_window_t>(XCB_WINDOW_NONE);
        gamescopeFocusState.saved = true;
        if (gamescopeFocusState.steamWindow != XCB_WINDOW_NONE) {
            setCardinal(connection, gamescopeFocusState.steamWindow, overlay, 0);
            setCardinal(connection, gamescopeFocusState.steamWindow, inputFocus, 0);
            setCardinal(connection, gamescopeFocusState.steamWindow, notification, 0);
        }
        saveGamescopeFocusState();
    }
    setCardinal(connection, window, overlay, 1);
    setCardinal(connection, window, inputFocus, 1);
    setAtom(connection, window, windowType, dockType);
    syncXcb(connection);
    xcb_disconnect(connection);
}

void restoreGamescopeOverlay(WId window)
{
    if (!gamescopeFocusState.saved)
        loadGamescopeFocusState();
    if (window == XCB_WINDOW_NONE)
        window = gamescopeFocusState.overlayWindow;
    int screen = 0;
    xcb_connection_t *connection = xcb_connect(nullptr, &screen);
    if (!connection || xcb_connection_has_error(connection)) {
        if (connection)
            xcb_disconnect(connection);
        return;
    }
    const auto atom = [connection](const char *name) {
        const auto cookie = xcb_intern_atom(connection, 0, static_cast<uint16_t>(strlen(name)), name);
        xcb_intern_atom_reply_t *reply = xcb_intern_atom_reply(connection, cookie, nullptr);
        const xcb_atom_t value = reply ? reply->atom : static_cast<xcb_atom_t>(XCB_ATOM_NONE);
        free(reply);
        return value;
    };
    if (window != XCB_WINDOW_NONE) {
        setCardinal(connection, window, atom("STEAM_OVERLAY"), 0);
        setCardinal(connection, window, atom("STEAM_INPUT_FOCUS"), 0);
    }
    if (gamescopeFocusState.steamWindow != XCB_WINDOW_NONE) {
        setCardinal(connection, gamescopeFocusState.steamWindow, atom("STEAM_OVERLAY"), gamescopeFocusState.steamOverlay);
        setCardinal(connection, gamescopeFocusState.steamWindow, atom("STEAM_INPUT_FOCUS"), gamescopeFocusState.steamInputFocus);
        setCardinal(connection, gamescopeFocusState.steamWindow, atom("STEAM_NOTIFICATION"), gamescopeFocusState.steamNotification);
    }
    syncXcb(connection);
    xcb_disconnect(connection);
    QFile::remove(gamescopeStateFile());
    gamescopeFocusState = {};
}

void cleanupGamescopeState()
{
    if (loadGamescopeFocusState())
        restoreGamescopeOverlay(XCB_WINDOW_NONE);
}

class QmlOverlayController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap config READ config NOTIFY configChanged)
    Q_PROPERTY(QVariantMap fanState READ fanState NOTIFY fanStateChanged)
    Q_PROPERTY(QVariantMap overlayConfig READ overlayConfig NOTIFY overlayConfigChanged)
    Q_PROPERTY(bool overlayVisible READ overlayVisible NOTIFY overlayVisibleChanged)
public:
    explicit QmlOverlayController(QObject *parent = nullptr)
        : QObject(parent)
    {
        overlayConfig_ = loadOverlayPreferences();
        QDir().mkpath(QFileInfo(controlSocket()).absolutePath());
        QLocalServer::removeServer(controlSocket());
        server_ = new QLocalServer(this);
        if (server_->listen(controlSocket()))
            connect(server_, &QLocalServer::newConnection, this, &QmlOverlayController::commands);
        connectInputEvents();
        inputDiscoveryTimer_.setInterval(5000);
        connect(&inputDiscoveryTimer_, &QTimer::timeout, this, &QmlOverlayController::connectInputEvents);
        inputDiscoveryTimer_.start();
        request(QStringLiteral("set_overlay_activation"), {{QStringLiteral("chord"), activeChord()}});
    }

    ~QmlOverlayController() override
    {
        hideOverlay();
        QLocalServer::removeServer(controlSocket());
    }

    QVariantMap config() const { return config_; }
    QVariantMap fanState() const { return fanState_; }
    QVariantMap overlayConfig() const { return overlayConfig_; }
    bool overlayVisible() const { return overlayVisible_; }

    Q_INVOKABLE QVariantMap call(const QString &action, const QVariantMap &fields = {})
    {
        const RpcResult result = request(action, QJsonObject::fromVariantMap(fields));
        return {
            {QStringLiteral("ok"), result.ok},
            {QStringLiteral("result"), result.result.toVariant()},
            {QStringLiteral("error"), result.error},
        };
    }

    Q_INVOKABLE QVariantMap steamCall(const QString &action, const QVariantMap &fields = {})
    {
        QProcess process;
        process.setProgram(qEnvironmentVariable("ARMADA_STEAM_BRIDGE", "/usr/libexec/armada/steam-bridge"));
        process.start();
        if (!process.waitForStarted(500))
            return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Steam bridge is unavailable")}};
        QJsonObject payload = QJsonObject::fromVariantMap(fields);
        payload.insert(QStringLiteral("action"), action);
        process.write(QJsonDocument(payload).toJson(QJsonDocument::Compact) + '\n');
        process.closeWriteChannel();
        if (!process.waitForFinished(6000)) {
            process.kill();
            process.waitForFinished(500);
            return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Steam bridge timed out")}};
        }
        const QJsonDocument response = QJsonDocument::fromJson(process.readAllStandardOutput());
        if (!response.isObject())
            return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Invalid Steam bridge response")}};
        return response.object().toVariantMap();
    }

    Q_INVOKABLE void refresh()
    {
        const RpcResult config = request(QStringLiteral("get_config"));
        if (!config.ok) {
            emit errorMessage(config.error);
            return;
        }
        config_ = config.result.toObject().toVariantMap();
        const RpcResult games = request(QStringLiteral("get_installed_games"));
        if (games.ok)
            config_.insert(QStringLiteral("installedGames"), games.result.toVariant());
        const RpcResult runtimeGame = request(QStringLiteral("get_runtime_game"));
        if (runtimeGame.ok && !runtimeGame.result.isNull())
            config_.insert(QStringLiteral("game"), runtimeGame.result.toObject().toVariantMap());
        const RpcResult fans = request(QStringLiteral("get_fans_state"));
        if (fans.ok)
            fanState_ = fans.result.toObject().toVariantMap();
        emit configChanged();
        emit fanStateChanged();
        if (!compatibilityTimer_.isActive()) {
            QTimer::singleShot(3000, this, &QmlOverlayController::compatibilitySweep);
            compatibilityTimer_.start();
        }
    }

    Q_INVOKABLE bool saveOverlayConfig(const QVariantMap &patch)
    {
        QVariantMap next = overlayConfig_;
        for (auto it = patch.cbegin(); it != patch.cend(); ++it) {
            if (next.contains(it.key()))
                next.insert(it.key(), it.value());
        }
        if (!validOverlayPreferences(next))
            return false;
        QSaveFile file(overlayPreferencesFile());
        if (!file.open(QIODevice::WriteOnly))
            return false;
        const QByteArray data = QJsonDocument::fromVariant(next).toJson(QJsonDocument::Indented);
        if (file.write(data) != data.size() || !file.commit())
            return false;
        overlayConfig_ = next;
        emit overlayConfigChanged();
        applyOverlayActivation();
        configureEdgeSensor();
        return true;
    }

    Q_INVOKABLE bool showOverlay()
    {
        if (!window_)
            return false;
        const RpcResult intercept = request(QStringLiteral("inputplumber_intercept"), {{QStringLiteral("mode"), QStringLiteral("overlay")} });
        if (!intercept.ok) {
            emit errorMessage(intercept.error);
            return false;
        }
        overlayVisible_ = true;
        emit overlayVisibleChanged();
        window_->setMask(QRegion());
        window_->show();
        window_->raise();
        window_->requestActivate();
        markGamescopeOverlay(window_->winId());
        QTimer::singleShot(0, this, [this] {
            if (window_ && window_->isVisible())
                markGamescopeOverlay(window_->winId());
        });
        return true;
    }

    Q_INVOKABLE void hideOverlay()
    {
        if (calibrationSessionActive_) {
            request(QStringLiteral("end_calibration_session"), {{QStringLiteral("token"), calibrationSessionToken_}});
            calibrationSessionActive_ = false;
        }
        request(QStringLiteral("inputplumber_intercept"), {{QStringLiteral("mode"), QStringLiteral("reset")} });
        overlayVisible_ = false;
        emit overlayVisibleChanged();
        if (window_) {
            restoreGamescopeOverlay(window_->winId());
            configureEdgeSensor();
        } else {
            cleanupGamescopeState();
        }
    }

    Q_INVOKABLE void toggleOverlay()
    {
        if (overlayVisible_)
            hideOverlay();
        else
            showOverlay();
    }

    void setWindow(QQuickWindow *window)
    {
        window_ = window;
        if (window_) {
            const QScreen *screen = QGuiApplication::primaryScreen();
            if (screen)
                window_->setGeometry(screen->availableGeometry());
        }
    }

    void prepareEdgeSensor()
    {
        edgeSensorReady_ = true;
        configureEdgeSensor();
    }

signals:
    void configChanged();
    void fanStateChanged();
    void overlayConfigChanged();
    void overlayVisibleChanged();
    void inputAction(const QString &action);
    void errorMessage(const QString &message);

private slots:
    void compatibilitySweep()
    {
        if (compatibilityProcess_.state() != QProcess::NotRunning)
            return;
        const QVariantMap tweaks = config_.value(QStringLiteral("tweaks")).toMap();
        const QVariantMap global = tweaks.value(QStringLiteral("global")).toMap();
        const RpcResult latestGames = request(QStringLiteral("get_installed_games"));
        if (latestGames.ok)
            config_.insert(QStringLiteral("installedGames"), latestGames.result.toVariant());
        const QVariantList games = config_.value(QStringLiteral("installedGames")).toList();
        if (games.isEmpty())
            return;
        const QVariantMap fields = {
            {QStringLiteral("games"), games},
            {QStringLiteral("tool"), global.value(QStringLiteral("windowsCompatTool")).toString()},
            {QStringLiteral("auto_apply"), global.value(QStringLiteral("autoApplyCompat"), true).toBool()},
        };
        QJsonObject payload = QJsonObject::fromVariantMap(fields);
        payload.insert(QStringLiteral("action"), QStringLiteral("sweep_compat"));
        compatibilityProcess_.setProgram(qEnvironmentVariable("ARMADA_STEAM_BRIDGE", "/usr/libexec/armada/steam-bridge"));
        compatibilityProcess_.start();
        if (!compatibilityProcess_.waitForStarted(500)) {
            compatibilityProcess_.kill();
            compatibilityProcess_.waitForFinished(500);
            return;
        }
        compatibilityProcess_.write(QJsonDocument(payload).toJson(QJsonDocument::Compact) + '\n');
        compatibilityProcess_.closeWriteChannel();
        QTimer::singleShot(7000, this, [this] {
            if (compatibilityProcess_.state() != QProcess::NotRunning) {
                compatibilityProcess_.kill();
                compatibilityProcess_.waitForFinished(500);
            }
        });
    }

    void onInputEvent(const QString &event, double value)
    {
        if (value <= 0.5)
            return;
        static const QHash<QString, QString> actions = {
            {QStringLiteral("Gamepad:Button:Guide"), QStringLiteral("guide")},
            {QStringLiteral("Gamepad:Button:QuickAccess"), QStringLiteral("guide")},
            {QStringLiteral("ui_guide"), QStringLiteral("guide")},
            {QStringLiteral("ui_quick_access"), QStringLiteral("guide")},
            {QStringLiteral("Gamepad:Button:DPadUp"), QStringLiteral("up")},
            {QStringLiteral("Gamepad:Button:DPadDown"), QStringLiteral("down")},
            {QStringLiteral("Gamepad:Button:DPadLeft"), QStringLiteral("left")},
            {QStringLiteral("Gamepad:Button:DPadRight"), QStringLiteral("right")},
            {QStringLiteral("Gamepad:Button:LeftBumper"), QStringLiteral("previous")},
            {QStringLiteral("Gamepad:Button:RightBumper"), QStringLiteral("next")},
            {QStringLiteral("Gamepad:Button:South"), QStringLiteral("accept")},
            {QStringLiteral("Gamepad:Button:East"), QStringLiteral("back")},
            {QStringLiteral("ui_up"), QStringLiteral("up")},
            {QStringLiteral("ui_down"), QStringLiteral("down")},
            {QStringLiteral("ui_left"), QStringLiteral("left")},
            {QStringLiteral("ui_right"), QStringLiteral("right")},
            {QStringLiteral("ui_l1"), QStringLiteral("previous")},
            {QStringLiteral("ui_r1"), QStringLiteral("next")},
            {QStringLiteral("ui_accept"), QStringLiteral("accept")},
            {QStringLiteral("ui_back"), QStringLiteral("back")},
        };
        const auto action = actions.constFind(event);
        if (action != actions.constEnd() && action.value() == QStringLiteral("guide")) {
            toggleOverlay();
            emit inputAction(QStringLiteral("guide"));
            return;
        }
        if (!window_ || !window_->isVisible())
            return;
        if (action != actions.constEnd())
            emit inputAction(action.value());
    }

    void commands()
    {
        while (server_->hasPendingConnections()) {
            QLocalSocket *socket = server_->nextPendingConnection();
            connect(socket, &QLocalSocket::readyRead, this, [this, socket] {
                const QString command = QString::fromUtf8(socket->readLine()).trimmed();
                if (command == QStringLiteral("show"))
                    showOverlay();
                else if (command == QStringLiteral("hide"))
                    hideOverlay();
                else if (command == QStringLiteral("toggle"))
                    toggleOverlay();
                socket->disconnectFromServer();
            });
        }
    }

private:
    void connectInputEvents()
    {
        const QString nextPath = discoverInputEventPath();
        if (nextPath == inputEventPath_)
            return;
        if (!inputEventPath_.isEmpty())
            QDBusConnection::systemBus().disconnect(
                QStringLiteral("org.shadowblip.InputPlumber"), inputEventPath_,
                QStringLiteral("org.shadowblip.Input.DBusDevice"), QStringLiteral("InputEvent"),
                this, SLOT(onInputEvent(QString,double)));
        inputEventPath_ = nextPath;
        if (!inputEventPath_.isEmpty())
            QDBusConnection::systemBus().connect(
                QStringLiteral("org.shadowblip.InputPlumber"), inputEventPath_,
                QStringLiteral("org.shadowblip.Input.DBusDevice"), QStringLiteral("InputEvent"),
                this, SLOT(onInputEvent(QString,double)));
    }

    QString activeChord() const
    {
        const QString key = overlayConfig_.value(QStringLiteral("layout")).toString() == QStringLiteral("side")
            ? QStringLiteral("sideChord") : QStringLiteral("centeredChord");
        return overlayConfig_.value(key).toString();
    }

    void applyOverlayActivation()
    {
        request(QStringLiteral("set_overlay_activation"), {{QStringLiteral("chord"), activeChord()}});
    }

    void configureEdgeSensor()
    {
        if (!window_)
            return;
        if (!edgeSensorReady_) {
            if (!overlayVisible_)
                window_->hide();
            return;
        }
        if (overlayVisible_ || !overlayConfig_.value(QStringLiteral("swipeEnabled")).toBool()) {
            window_->setMask(QRegion());
            if (!overlayVisible_ && !overlayConfig_.value(QStringLiteral("swipeEnabled")).toBool())
                window_->hide();
            else
                window_->show();
            return;
        }
        const QRect bounds = window_->rect();
        const int width = qBound(16, bounds.width() / 40, 48);
        const QString edge = overlayConfig_.value(QStringLiteral("swipeEdge")).toString();
        QRegion mask;
        if (edge == QStringLiteral("left"))
            mask = QRegion(0, 0, width, bounds.height());
        else if (edge == QStringLiteral("right"))
            mask = QRegion(bounds.width() - width, 0, width, bounds.height());
        else
            mask = QRegion(0, bounds.height() - width, bounds.width(), width);
        window_->setMask(mask);
        window_->show();
    }

    QQuickWindow *window_ = nullptr;
    QLocalServer *server_ = nullptr;
    QVariantMap config_;
    QVariantMap fanState_;
    QVariantMap overlayConfig_;
    bool overlayVisible_ = false;
    bool edgeSensorReady_ = false;
    QTimer compatibilityTimer_;
    QTimer inputDiscoveryTimer_;
    QProcess compatibilityProcess_;
    QString inputEventPath_;
    QString calibrationSessionToken_;
    bool calibrationSessionActive_ = false;
};

} // namespace

int main(int argc, char **argv)
{
    const QString command = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QString();
    const bool persistent = command == QStringLiteral("--persistent");
    if (qEnvironmentVariableIsEmpty("DISPLAY")) {
        const QString display = discoverGamescopeDisplay();
        if (!display.isEmpty())
            qputenv("DISPLAY", display.toLocal8Bit());
    }
    if (command == QStringLiteral("--cleanup")) {
        cleanupGamescopeState();
        return 0;
    }
    if (command == QStringLiteral("--show") || command == QStringLiteral("--hide") || command == QStringLiteral("--toggle"))
        return sendCommand(command.mid(2)) ? 0 : 1;

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Armada Control"));
    QQuickWindow::setDefaultAlphaBuffer(true);
    QQmlApplicationEngine engine;
    QmlOverlayController controller;
    engine.rootContext()->setContextProperty(QStringLiteral("armada"), &controller);
    const QString qmlPath = qEnvironmentVariable("ARMADA_OVERLAY_QML", "/usr/share/armada/overlay/Main.qml");
    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    if (!window)
        return 1;
    controller.setWindow(window);
    controller.refresh();
    if (persistent)
        controller.prepareEdgeSensor();
    if (!persistent && command == QStringLiteral("--standalone"))
        controller.showOverlay();
    return app.exec();
}

#include "main.moc"
