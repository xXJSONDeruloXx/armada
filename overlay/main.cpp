#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDBusConnection>
#include <QDir>
#include <QFileInfo>
#include <QFormLayout>
#include <QGroupBox>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QLocalServer>
#include <QLocalSocket>
#include <QMainWindow>
#include <QPushButton>
#include <QScrollArea>
#include <QSpinBox>
#include <QTabWidget>
#include <QTimer>
#include <QVBoxLayout>
#include <QWindow>
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

void markGamescopeOverlay(WId window)
{
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
        const xcb_atom_t value = reply ? reply->atom : XCB_ATOM_NONE;
        free(reply);
        return value;
    };
    const xcb_atom_t overlay = atom("STEAM_OVERLAY");
    const xcb_atom_t inputFocus = atom("STEAM_INPUT_FOCUS");
    const xcb_atom_t windowType = atom("_NET_WM_WINDOW_TYPE");
    const xcb_atom_t dockType = atom("_NET_WM_WINDOW_TYPE_DOCK");
    const uint32_t enabled = 1;
    if (overlay != XCB_ATOM_NONE)
        xcb_change_property(connection, XCB_PROP_MODE_REPLACE, window, overlay,
            XCB_ATOM_CARDINAL, 32, 1, &enabled);
    if (inputFocus != XCB_ATOM_NONE)
        xcb_change_property(connection, XCB_PROP_MODE_REPLACE, window, inputFocus,
            XCB_ATOM_CARDINAL, 32, 1, &enabled);
    if (windowType != XCB_ATOM_NONE && dockType != XCB_ATOM_NONE)
        xcb_change_property(connection, XCB_PROP_MODE_REPLACE, window, windowType,
            XCB_ATOM_ATOM, 32, 1, &dockType);
    xcb_flush(connection);
    xcb_disconnect(connection);
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
        request(QStringLiteral("inputplumber_intercept"), {{QStringLiteral("mode"), QStringLiteral("reset")} });
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

    void saveProfile(const QString &label)
    {
        if (loading_ || label.isEmpty())
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
        markGamescopeOverlay(winId());
        show();
        markGamescopeOverlay(winId());
        raise();
        activateWindow();
    }

    void hideOverlay()
    {
        request(QStringLiteral("inputplumber_intercept"), {{QStringLiteral("mode"), QStringLiteral("reset")} });
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
