#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDBusConnection>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFormLayout>
#include <QGroupBox>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QLocalServer>
#include <QLocalSocket>
#include <QMainWindow>
#include <QPushButton>
#include <QRegularExpression>
#include <QSpinBox>
#include <QTabWidget>
#include <QTimer>
#include <QVBoxLayout>
#include <QStringList>
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
    if (!socket.waitForReadyRead(5000))
        return {false, {}, QStringLiteral("Armada service did not respond")};
    QByteArray line = socket.readLine();
    QJsonParseError parseError;
    const QJsonDocument response = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError || !response.isObject())
        return {false, {}, QStringLiteral("Invalid Armada service response")};
    const QJsonObject object = response.object();
    if (!object.value(QStringLiteral("ok")).toBool())
        return {false, {}, object.value(QStringLiteral("error")).toString()};
    return {true, object.value(QStringLiteral("result")), {}};
}

QString controlSocket()
{
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    return (runtime.isEmpty() ? QStringLiteral("/run/user/%1").arg(QString::number(getuid())) : runtime)
        + QStringLiteral("/armada-control-overlay/control.sock");
}

bool sendCommand(const QString &command)
{
    QLocalSocket socket;
    socket.connectToServer(controlSocket());
    if (!socket.waitForConnected(200))
        return false;
    socket.write(command.toUtf8() + '\n');
    socket.flush();
    return socket.waitForBytesWritten(200);
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
    const QRegularExpression displayPattern(QStringLiteral("^X(\\d+)$"));
    const QStringList sockets = QDir(QStringLiteral("/tmp/.X11-unix"))
        .entryList(QDir::System | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &socket : sockets) {
        const QRegularExpressionMatch match = displayPattern.match(socket);
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

bool getCardinal(xcb_connection_t *connection, xcb_window_t window, xcb_atom_t property, uint32_t *value)
{
    const auto cookie = xcb_get_property(connection, 0, window, property, XCB_ATOM_CARDINAL, 0, 1);
    xcb_get_property_reply_t *reply = xcb_get_property_reply(connection, cookie, nullptr);
    if (!reply || reply->format != 32 || reply->value_len < 1) {
        free(reply);
        return false;
    }
    *value = *static_cast<const uint32_t *>(xcb_get_property_value(reply));
    free(reply);
    return true;
}

void setCardinal(xcb_connection_t *connection, xcb_window_t window, xcb_atom_t property, uint32_t value)
{
    if (property != XCB_ATOM_NONE)
        xcb_change_property(connection, XCB_PROP_MODE_REPLACE, window, property,
            XCB_ATOM_CARDINAL, 32, 1, &value);
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

    auto atom = [connection](const char *name) {
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
    const uint32_t enabled = 1;
    if (!gamescopeFocusState.saved) {
        const xcb_screen_t *screenInfo = xcb_setup_roots_iterator(xcb_get_setup(connection)).data;
        gamescopeFocusState.steamWindow = screenInfo
            ? findSteamWindow(connection, screenInfo->root, wmClass)
            : static_cast<xcb_window_t>(XCB_WINDOW_NONE);
        if (gamescopeFocusState.steamWindow != XCB_WINDOW_NONE) {
            getCardinal(connection, gamescopeFocusState.steamWindow, overlay, &gamescopeFocusState.steamOverlay);
            getCardinal(connection, gamescopeFocusState.steamWindow, inputFocus, &gamescopeFocusState.steamInputFocus);
            getCardinal(connection, gamescopeFocusState.steamWindow, notification, &gamescopeFocusState.steamNotification);
            gamescopeFocusState.saved = true;
            saveGamescopeFocusState();
            setCardinal(connection, gamescopeFocusState.steamWindow, overlay, 0);
            setCardinal(connection, gamescopeFocusState.steamWindow, inputFocus, 0);
            setCardinal(connection, gamescopeFocusState.steamWindow, notification, 0);
        }
    }
    setCardinal(connection, window, overlay, enabled);
    setCardinal(connection, window, inputFocus, enabled);
    if (windowType != XCB_ATOM_NONE && dockType != XCB_ATOM_NONE)
        xcb_change_property(connection, XCB_PROP_MODE_REPLACE, window, windowType,
            XCB_ATOM_ATOM, 32, 1, &dockType);
    xcb_flush(connection);
    xcb_disconnect(connection);
}

void restoreGamescopeOverlay(WId window)
{
    if (!gamescopeFocusState.saved)
        loadGamescopeFocusState();
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
    xcb_flush(connection);
    xcb_disconnect(connection);
    QFile::remove(gamescopeStateFile());
    gamescopeFocusState = {};
}

void cleanupGamescopeState()
{
    if (loadGamescopeFocusState())
        restoreGamescopeOverlay(XCB_WINDOW_NONE);
}

class OverlayWindow final : public QMainWindow {
    Q_OBJECT
public:
    explicit OverlayWindow(bool persistent)
        : persistent_(persistent)
    {
        setWindowTitle(QStringLiteral("Armada Control"));
        setWindowFlags(Qt::Tool | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
        setAttribute(Qt::WA_DeleteOnClose, false);
        resize(720, 560);

        tabs_ = new QTabWidget(this);
        setCentralWidget(tabs_);
        buildStatusPage();
        buildPowerPage();
        buildFansPage();
        buildSettingsPage();

        server_ = new QLocalServer(this);
        QDir().mkpath(QFileInfo(controlSocket()).absolutePath());
        QLocalServer::removeServer(controlSocket());
        if (server_->listen(controlSocket()))
            connect(server_, &QLocalServer::newConnection, this, &OverlayWindow::commands);
        QDBusConnection::systemBus().connect(
            QStringLiteral("org.shadowblip.InputPlumber"),
            QStringLiteral("/org/shadowblip/InputPlumber/devices/target/dbus0"),
            QStringLiteral("org.shadowblip.Input.DBusDevice"),
            QStringLiteral("InputEvent"), this, SLOT(onInputEvent(QString,double)));

        connect(&refreshTimer_, &QTimer::timeout, this, &OverlayWindow::reload);
        refreshTimer_.start(2000);
        request(QStringLiteral("set_overlay_activation"));
        reload();
        if (persistent_)
            hide();
        else
            showOverlay();
    }

    ~OverlayWindow() override
    {
        hideOverlay();
        QLocalServer::removeServer(controlSocket());
    }

private slots:
    void onInputEvent(const QString &event, double value)
    {
        const bool pressed = value > 0.5;
        if (event == QStringLiteral("Gamepad:Button:Guide") && pressed) {
            isVisible() ? hideOverlay() : showOverlay();
            return;
        }
        if (!isVisible())
            return;
        int key = 0;
        if (event == QStringLiteral("Gamepad:Button:DPadUp")) key = Qt::Key_Up;
        if (event == QStringLiteral("Gamepad:Button:DPadDown")) key = Qt::Key_Down;
        if (event == QStringLiteral("Gamepad:Button:DPadLeft")) key = Qt::Key_Left;
        if (event == QStringLiteral("Gamepad:Button:DPadRight")) key = Qt::Key_Right;
        if (event == QStringLiteral("Gamepad:Button:South")) key = Qt::Key_Return;
        if (event == QStringLiteral("Gamepad:Button:East")) key = Qt::Key_Escape;
        if (event == QStringLiteral("Gamepad:Button:Start")) key = Qt::Key_Tab;
        if (event == QStringLiteral("Gamepad:Button:Select")) key = Qt::Key_Backspace;
        if (key)
            QCoreApplication::postEvent(focusWidget(), new QKeyEvent(
                pressed ? QEvent::KeyPress : QEvent::KeyRelease, key, Qt::NoModifier));
    }

    void buildStatusPage()
    {
        auto *page = new QWidget;
        auto *layout = new QVBoxLayout(page);
        status_ = new QLabel(QStringLiteral("Loading Armada Control…"));
        status_->setWordWrap(true);
        layout->addWidget(status_);

        auto *refresh = new QPushButton(QStringLiteral("Refresh"));
        connect(refresh, &QPushButton::clicked, this, &OverlayWindow::reload);
        layout->addWidget(refresh);
        layout->addStretch();
        tabs_->addTab(page, QStringLiteral("Status"));
    }

    void buildPowerPage()
    {
        auto *page = new QWidget;
        auto *layout = new QFormLayout(page);
        profile_ = new QComboBox;
        connect(profile_, &QComboBox::currentTextChanged, this, &OverlayWindow::saveProfile);
        layout->addRow(QStringLiteral("Power profile"), profile_);
        layout->addRow(QStringLiteral("Temperature"), temp_ = new QLabel(QStringLiteral("—")));
        layout->addRow(QStringLiteral("Active fan curve"), fanCurve_ = new QLabel(QStringLiteral("—")));
        tabs_->addTab(page, QStringLiteral("Power"));
    }

    void buildFansPage()
    {
        auto *page = new QWidget;
        auto *layout = new QVBoxLayout(page);
        fanSummary_ = new QLabel(QStringLiteral("Loading fan state…"));
        fanSummary_->setWordWrap(true);
        layout->addWidget(fanSummary_);
        layout->addStretch();
        tabs_->addTab(page, QStringLiteral("Fans"));
    }

    void buildSettingsPage()
    {
        auto *page = new QWidget;
        auto *layout = new QFormLayout(page);
        controller_ = new QComboBox;
        controller_->addItem(QStringLiteral("Steam Deck"), QStringLiteral("deck-uhid"));
        controller_->addItem(QStringLiteral("Xbox 360"), QStringLiteral("xb360"));
        controller_->addItem(QStringLiteral("DualSense"), QStringLiteral("ds5"));
        connect(controller_, &QComboBox::currentIndexChanged, this, [this](int index) {
            if (loading_ || index < 0)
                return;
            request(QStringLiteral("set_controller_type"), {
                {QStringLiteral("value"), controller_->itemData(index).toString()}
            });
        });
        layout->addRow(QStringLiteral("Controller"), controller_);

        ssh_ = new QCheckBox(QStringLiteral("Enable SSH"));
        mtp_ = new QCheckBox(QStringLiteral("USB file transfer"));
        abl_ = new QCheckBox(QStringLiteral("Automatic ABL updates"));
        layout->addRow(ssh_);
        layout->addRow(mtp_);
        layout->addRow(abl_);
        connect(ssh_, &QCheckBox::toggled, this, [this](bool checked) { setToggle("set_ssh_enabled", checked); });
        connect(mtp_, &QCheckBox::toggled, this, [this](bool checked) { setToggle("set_mtp_enabled", checked); });
        connect(abl_, &QCheckBox::toggled, this, [this](bool checked) { setToggle("set_abl_auto_enabled", checked); });

        auto *rgb = new QGroupBox(QStringLiteral("RGB lighting"));
        auto *rgbLayout = new QFormLayout(rgb);
        rgbEnabled_ = new QCheckBox;
        rgbColor_ = new QLineEdit;
        rgbColor_->setPlaceholderText(QStringLiteral("FFFFFF"));
        rgbBrightness_ = new QSpinBox;
        rgbBrightness_->setRange(0, 100);
        auto *applyRgb = new QPushButton(QStringLiteral("Apply RGB"));
        rgbLayout->addRow(QStringLiteral("Enabled"), rgbEnabled_);
        rgbLayout->addRow(QStringLiteral("Color"), rgbColor_);
        rgbLayout->addRow(QStringLiteral("Brightness"), rgbBrightness_);
        rgbLayout->addRow(applyRgb);
        connect(applyRgb, &QPushButton::clicked, this, [this] {
            request(QStringLiteral("set_rgb"), {
                {QStringLiteral("enabled"), rgbEnabled_->isChecked()},
                {QStringLiteral("color"), rgbColor_->text()},
                {QStringLiteral("brightness"), rgbBrightness_->value()},
            });
            reload();
        });
        layout->addRow(rgb);
        layout->addRow(QStringLiteral("OS version"), osVersion_ = new QLabel(QStringLiteral("—")));
        layout->addRow(QStringLiteral("ABL version"), ablVersion_ = new QLabel(QStringLiteral("—")));
        tabs_->addTab(page, QStringLiteral("Settings"));
    }

    void setToggle(const QString &action, bool value)
    {
        if (loading_)
            return;
        const RpcResult result = request(action, {{QStringLiteral("enabled"), value}});
        if (!result.ok)
            status_->setText(result.error);
        reload();
    }

    void reload()
    {
        const RpcResult config = request(QStringLiteral("get_config"));
        if (!config.ok) {
            status_->setText(config.error);
            return;
        }
        loading_ = true;
        config_ = config.result.toObject();
        const QJsonObject general = config_.value(QStringLiteral("power")).toObject().value(QStringLiteral("general")).toObject();
        const QJsonObject profiles = config_.value(QStringLiteral("power")).toObject().value(QStringLiteral("profiles")).toObject();
        profile_->clear();
        for (const QString &name : profiles.keys())
            profile_->addItem(profiles.value(name).toObject().value(QStringLiteral("label")).toString(name), name);
        const QString selected = general.value(QStringLiteral("default_profile")).toString();
        const int profileIndex = profile_->findData(selected);
        if (profileIndex >= 0)
            profile_->setCurrentIndex(profileIndex);

        const QString controller = config_.value(QStringLiteral("controllerType")).toString();
        const int controllerIndex = controller_->findData(controller);
        if (controllerIndex >= 0)
            controller_->setCurrentIndex(controllerIndex);
        ssh_->setChecked(config_.value(QStringLiteral("sshEnabled")).toBool());
        mtp_->setChecked(config_.value(QStringLiteral("mtpEnabled")).toBool());
        abl_->setChecked(config_.value(QStringLiteral("ablAutoEnabled")).toBool());
        osVersion_->setText(config_.value(QStringLiteral("osVersion")).toString(QStringLiteral("unknown")));
        ablVersion_->setText(config_.value(QStringLiteral("ablVersion")).toString(QStringLiteral("unknown")));

        const RpcResult rgb = request(QStringLiteral("get_rgb"));
        if (rgb.ok && rgb.result.isObject()) {
            const QJsonObject value = rgb.result.toObject();
            rgbEnabled_->setChecked(value.value(QStringLiteral("enabled")).toBool());
            rgbColor_->setText(value.value(QStringLiteral("color")).toString());
            rgbBrightness_->setValue(value.value(QStringLiteral("brightness")).toInt());
        }
        const RpcResult fans = request(QStringLiteral("get_fans_state"));
        if (fans.ok) {
            const QJsonObject value = fans.result.toObject();
            const int current = value.value(QStringLiteral("currentTemp")).toInt(-1);
            temp_->setText(current < 0 ? QStringLiteral("—") : QStringLiteral("%1 °C").arg(current));
            fanCurve_->setText(value.value(QStringLiteral("activeProfile")).toString(QStringLiteral("—")));
            QStringList curves;
            const QJsonObject curveValues = value.value(QStringLiteral("fanCurves")).toObject();
            for (const QString &name : curveValues.keys())
                curves << QStringLiteral("%1: %2").arg(name, curveValues.value(name).toObject().value(QStringLiteral("curve")).toString());
            fanSummary_->setText(curves.isEmpty() ? QStringLiteral("No fan curves reported") : curves.join('\n'));
        }
        status_->setText(QStringLiteral("Armada Control API v%1 · %2")
            .arg(request(QStringLiteral("get_capabilities")).result.toObject().value(QStringLiteral("api")).toInt(1))
            .arg(config_.value(QStringLiteral("cpuDeviceClass")).toString(QStringLiteral("device unavailable"))));
        loading_ = false;
    }

    void saveProfile(const QString &)
    {
        if (loading_ || profile_->currentText().isEmpty())
            return;
        const QString profile = profile_->currentData().toString();
        QJsonObject power = config_.value(QStringLiteral("power")).toObject();
        QJsonObject general = power.value(QStringLiteral("general")).toObject();
        general.insert(QStringLiteral("default_profile"), profile);
        power.insert(QStringLiteral("general"), general);
        const RpcResult result = request(QStringLiteral("save_power_config"), {{QStringLiteral("data"), power}});
        if (!result.ok)
            status_->setText(result.error);
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
                    isVisible() ? hideOverlay() : showOverlay();
                socket->disconnectFromServer();
            });
        }
    }

    void showOverlay()
    {
        const RpcResult intercept = request(QStringLiteral("inputplumber_intercept"), {{QStringLiteral("mode"), QStringLiteral("overlay")} });
        if (!intercept.ok)
            status_->setText(intercept.error);
        show();
        markGamescopeOverlay(winId());
        raise();
        activateWindow();
    }

    void hideOverlay()
    {
        request(QStringLiteral("inputplumber_intercept"), {{QStringLiteral("mode"), QStringLiteral("reset")} });
        restoreGamescopeOverlay(winId());
        hide();
    }

private:
    QTabWidget *tabs_ = nullptr;
    QLabel *status_ = nullptr;
    QLabel *temp_ = nullptr;
    QLabel *fanCurve_ = nullptr;
    QLabel *fanSummary_ = nullptr;
    QLabel *osVersion_ = nullptr;
    QLabel *ablVersion_ = nullptr;
    QComboBox *profile_ = nullptr;
    QComboBox *controller_ = nullptr;
    QCheckBox *ssh_ = nullptr;
    QCheckBox *mtp_ = nullptr;
    QCheckBox *abl_ = nullptr;
    QCheckBox *rgbEnabled_ = nullptr;
    QLineEdit *rgbColor_ = nullptr;
    QSpinBox *rgbBrightness_ = nullptr;
    QJsonObject config_;
    QTimer refreshTimer_;
    QLocalServer *server_ = nullptr;
    bool loading_ = false;
    bool persistent_ = false;
};

} // namespace

int main(int argc, char **argv)
{
    const bool persistent = argc > 1 && QString::fromLocal8Bit(argv[1]) == QStringLiteral("--persistent");
    const QString command = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QString();
    if (qEnvironmentVariableIsEmpty("DISPLAY")) {
        const QString display = discoverGamescopeDisplay();
        if (!display.isEmpty())
            qputenv("DISPLAY", display.toLocal8Bit());
    }
    if (command == QStringLiteral("--cleanup")) {
        cleanupGamescopeState();
        return 0;
    }
    if (command == QStringLiteral("--show") || command == QStringLiteral("--hide") || command == QStringLiteral("--toggle")) {
        if (sendCommand(command.mid(2)))
            return 0;
        if (command != QStringLiteral("--standalone"))
            return 1;
    }

    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Armada Control"));
    app.setStyle(QStringLiteral("Fusion"));
    QPalette palette = app.palette();
    palette.setColor(QPalette::Window, QColor(27, 29, 33));
    palette.setColor(QPalette::WindowText, QColor(235, 235, 235));
    palette.setColor(QPalette::Base, QColor(20, 22, 25));
    palette.setColor(QPalette::AlternateBase, QColor(35, 38, 43));
    palette.setColor(QPalette::Text, QColor(235, 235, 235));
    palette.setColor(QPalette::Button, QColor(45, 49, 56));
    palette.setColor(QPalette::ButtonText, QColor(235, 235, 235));
    palette.setColor(QPalette::Highlight, QColor(26, 115, 232));
    palette.setColor(QPalette::HighlightedText, Qt::white);
    app.setPalette(palette);
    OverlayWindow window(persistent);
    return app.exec();
}

#include "main.moc"
