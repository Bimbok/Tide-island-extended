#include "WifiController.h"
#include "BluetoothPairingAgent.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QThread>
#include <QtTest>
#include <cstdio>
#include <memory>

using Paths = QList<QDBusObjectPath>;
using Settings = QMap<QString, QVariantMap>;
using ManagedObjects = QMap<QDBusObjectPath, Settings>;
using OrderedNetworks = QList<std::pair<QDBusObjectPath, qint16>>;
Q_DECLARE_METATYPE(Paths)
Q_DECLARE_METATYPE(Settings)
Q_DECLARE_METATYPE(ManagedObjects)
Q_DECLARE_METATYPE(OrderedNetworks)

namespace {
constexpr auto nmService = "org.freedesktop.NetworkManager";
constexpr auto nmPath = "/org/freedesktop/NetworkManager";
constexpr auto nmDevice = "/org/freedesktop/NetworkManager/Devices/1";
constexpr auto nmAp = "/org/freedesktop/NetworkManager/AccessPoint/";
constexpr auto propertiesInterface = "org.freedesktop.DBus.Properties";
constexpr auto testInterface = "org.tideisland.Test";

// A separate process owns the fake services so delayed replies exercise real
// D-Bus dispatch, rather than Qt's same-process method-call shortcut.
class FakeWifiService : public QDBusVirtualObject {
public:
    explicit FakeWifiService(bool iwd) : m_iwd(iwd) {}
    QString introspect(const QString &) const override { return {}; }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &bus) override {
        if (message.interface() == QLatin1String(testInterface)) {
            if (message.member() == QLatin1String("Configure")) {
                const auto config = qdbus_cast<QVariantMap>(message.arguments().value(0));
                m_delay = config.value("delay", m_delay).toInt();
                m_failList = config.value("failList", m_failList).toBool();
                const bool enabled = config.value("enabled", m_enabled).toBool();
                const bool changed = enabled != m_enabled;
                m_enabled = enabled;
                bus.send(message.createReply());
                if (changed && !m_iwd) {
                    auto signal = QDBusMessage::createSignal(nmPath, propertiesInterface, "PropertiesChanged");
                    signal.setArguments({QString(nmService), QVariantMap {{"WirelessEnabled", enabled}}, QStringList {}});
                    bus.send(signal);
                }
            } else if (message.member() == QLatin1String("Counters")) {
                bus.send(message.createReply(QList<QVariant> {m_counters}));
            } else if (message.member() == QLatin1String("EmitNetworkAdded")) {
                bus.send(message.createReply());
                auto signal = QDBusMessage::createSignal("/", "org.freedesktop.DBus.ObjectManager", "InterfacesAdded");
                const Settings interfaces {{"net.connman.iwd.Network", {{"Name", "Cafe"}, {"Type", "open"}}}};
                signal.setArguments({QVariant::fromValue(QDBusObjectPath("/iwd/cafe")), QVariant::fromValue(interfaces)});
                bus.send(signal);
            }
            return true;
        }

        QList<QVariant> arguments;
        bool delayed = false;
        auto count = [this](const QString &key) { m_counters[key] = m_counters.value(key).toInt() + 1; };
        if (message.interface() == QLatin1String(propertiesInterface)) {
            if (message.member() == QLatin1String("Get")) {
                count("get");
                bus.send(message.createErrorReply(QDBusError::UnknownProperty, "Use GetAll"));
                return true;
            }
            if (message.member() != QLatin1String("GetAll"))
                return false;
            QVariantMap values;
            const auto interface = message.arguments().value(0).toString();
            if (interface == QLatin1String(nmService)) {
                count("snapshots");
                values = {{"WirelessEnabled", m_enabled}, {"Devices", QVariant::fromValue(Paths {QDBusObjectPath(nmDevice)})}};
            } else if (interface.endsWith(QLatin1String(".Device.Wireless"))) {
                values = {{"ActiveAccessPoint", QVariant::fromValue(QDBusObjectPath(QString(nmAp) + "1"))}};
            } else if (interface.endsWith(QLatin1String(".Device"))) {
                values = {{"DeviceType", uint(2)}};
            } else if (interface.endsWith(QLatin1String(".AccessPoint"))) {
                count("apReads");
                count(message.path());
                const auto id = message.path().section('/', -1).toInt();
                const QByteArray ssid = id <= 2 ? "Home" : (id == 3 ? "Cafe" : "Guest");
                values = {{"Ssid", ssid}, {"Strength", uchar(id == 1 ? 35 : (id == 2 ? 85 : 70))},
                          {"Flags", uint(id <= 2 ? 1 : 0)}, {"WpaFlags", uint(0)}, {"RsnFlags", uint(0)}};
                delayed = true;
            }
            arguments = {values};
        } else if (message.member() == QLatin1String("GetAllAccessPoints")) {
            if (m_failList) {
                bus.send(message.createErrorReply(QDBusError::Failed, "AP list unavailable"));
                return true;
            }
            Paths paths;
            for (int i = 1; i <= 4; ++i) paths.append(QDBusObjectPath(QString(nmAp) + QString::number(i)));
            arguments = {QVariant::fromValue(paths)};
        } else if (message.member() == QLatin1String("ListConnections")) {
            count("savedReads");
            arguments = {QVariant::fromValue(Paths {QDBusObjectPath("/saved/1")})};
        } else if (message.member() == QLatin1String("GetSettings")) {
            const Settings settings {{"connection", {{"type", "802-11-wireless"}}},
                                     {"802-11-wireless", {{"ssid", QByteArray("Home")}}}};
            arguments = {QVariant::fromValue(settings)};
        } else if (message.member() == QLatin1String("RequestScan") || message.member() == QLatin1String("Scan")) {
            count("scans");
        } else if (message.member() == QLatin1String("GetManagedObjects")) {
            count("snapshots");
            const auto objectPath = [](const char *path) { return QVariant::fromValue(QDBusObjectPath(path)); };
            const ManagedObjects objects {
                {QDBusObjectPath("/iwd/device"), {
                    {"net.connman.iwd.Device", {{"Powered", m_enabled}}},
                    {"net.connman.iwd.Station", {{"State", "connected"}, {"Scanning", false},
                                                {"ConnectedNetwork", objectPath("/iwd/home")}}}}},
                {QDBusObjectPath("/iwd/home"), {{"net.connman.iwd.Network", {
                    {"Name", "Home"}, {"Type", "psk"}, {"Connected", true}, {"KnownNetwork", objectPath("/known/home")}}}}},
                {QDBusObjectPath("/iwd/cafe"), {{"net.connman.iwd.Network", {
                    {"Name", "Cafe"}, {"Type", "open"}, {"Connected", false}, {"KnownNetwork", objectPath("/")}}}}}
            };
            arguments = {QVariant::fromValue(objects)};
            delayed = true;
        } else if (message.member() == QLatin1String("GetOrderedNetworks")) {
            count("orderedReads");
            const OrderedNetworks networks {{QDBusObjectPath("/iwd/home"), -5500}, {QDBusObjectPath("/iwd/cafe"), -6500}};
            arguments = {QVariant::fromValue(networks)};
        } else {
            bus.send(message.createErrorReply(QDBusError::UnknownMethod, message.member()));
            return true;
        }
        const auto reply = message.createReply(arguments);
        if (delayed && m_delay > 0) {
            message.setDelayedReply(true);
            QTimer::singleShot(m_delay, this, [bus, reply]() { bus.send(reply); });
        } else {
            bus.send(reply);
        }
        return true;
    }
private:
    bool m_iwd;
    bool m_enabled = true;
    bool m_failList = false;
    int m_delay = 0;
    QVariantMap m_counters;
};
}

class WifiControllerTests : public QObject {
    Q_OBJECT
private:
    QProcess m_helper;
    QString m_service;

    void startService(bool iwd = false) {
        m_service = iwd ? QStringLiteral("net.connman.iwd") : QString(nmService);
        m_helper.start(QCoreApplication::applicationFilePath(), {iwd ? "--fake-iwd" : "--fake-networkmanager"});
        QVERIFY(m_helper.waitForStarted(2000));
        QVERIFY(m_helper.waitForReadyRead(2000));
        QCOMPARE(m_helper.readAllStandardOutput().trimmed(), QByteArray("ready"));
    }
    QVariantMap control(const QString &method, const QList<QVariant> &arguments = {}) {
        auto message = QDBusMessage::createMethodCall(m_service, "/test", testInterface, method);
        message.setArguments(arguments);
        const auto reply = QDBusConnection::systemBus().call(message, QDBus::Block, 1000);
        if (reply.type() == QDBusMessage::ErrorMessage)
            QTest::qFail(qPrintable(reply.errorMessage()), __FILE__, __LINE__);
        return qdbus_cast<QVariantMap>(reply.arguments().value(0));
    }
    void configure(const QVariantMap &config) { control("Configure", {config}); }
    QVariantMap counters() { return control("Counters"); }
    static QVariant row(WifiController &wifi, int index, int role) {
        return wifi.networks()->data(wifi.networks()->index(index, 0), role);
    }
private slots:
    void initTestCase() {
        // Use the same declarative registration as the production QML plugin.
        // Registering a prebuilt instance would hide broken QML annotations.
        qmlRegisterTypesAndRevisions<WifiController>("TideIsland.ConnectivityTests", 1);
        qmlRegisterTypesAndRevisions<BluetoothPairingAgent>("TideIsland.ConnectivityTests", 1);
    }

    void qmlSingletonIsUsable_data() {
        QTest::addColumn<QString>("typeName");
        QTest::addColumn<QString>("methodName");
        QTest::addColumn<QString>("propertyName");
        QTest::newRow("wifi") << QString("WifiController") << QString("refreshState") << QString("enabled");
        QTest::newRow("bluetooth-pairing") << QString("BluetoothPairingAgent") << QString("cancelRequest") << QString("requestActive");
    }

    void qmlSingletonIsUsable() {
        QFETCH(QString, typeName);
        QFETCH(QString, methodName);
        QFETCH(QString, propertyName);
        startService();
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData(QString(R"(
            import QtQml
            import TideIsland.ConnectivityTests 1.0
            QtObject {
                readonly property var controller: %1
                readonly property var state: controller.%2
                readonly property bool callable: typeof controller.%3 === "function"
                readonly property var ssid: %1 === WifiController ? controller.currentSsid : ""
                function refresh() { controller.clearMessages(); controller.refreshState(); }
            }
        )").arg(typeName, propertyName, methodName).toUtf8(), QUrl());
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> consumer(component.create());
        QVERIFY2(consumer, qPrintable(component.errorString()));
        QVERIFY2(consumer->property("state").isValid(), "QML singleton has no state properties");
        QVERIFY2(consumer->property("callable").toBool(), "QML singleton has no invokable methods");
        if (typeName == QLatin1String("WifiController")) {
            QTRY_COMPARE(consumer->property("ssid").toString(), QString("Home"));
            QVERIFY(consumer->property("state").toBool());
            QVERIFY(QMetaObject::invokeMethod(consumer.get(), "refresh"));
            configure({{"enabled", false}});
            QTRY_VERIFY(!consumer->property("state").toBool());
            QTRY_COMPARE(consumer->property("ssid").toString(), QString());
            configure({{"enabled", true}});
            QTRY_VERIFY(consumer->property("state").toBool());
            QTRY_COMPARE(consumer->property("ssid").toString(), QString("Home"));
        } else {
            QVERIFY(!consumer->property("state").toBool());
        }
    }

    void cleanup() {
        m_helper.kill();
        m_helper.waitForFinished(2000);
        QCoreApplication::processEvents();
    }

    void refreshKeepsEventLoopResponsiveAndBatchesProperties() {
        startService();
        configure({{"delay", 100}});
        int ticks = 0;
        QTimer heartbeat;
        connect(&heartbeat, &QTimer::timeout, this, [&]() { ++ticks; });
        heartbeat.start(10);
        QElapsedTimer elapsed;
        elapsed.start();
        WifiController wifi;
        QVERIFY(elapsed.elapsed() < 100);
        bool wrongThread = false;
        connect(wifi.networks(), &QAbstractItemModel::modelReset, this, [&]() {
            wrongThread |= QThread::currentThread() != wifi.thread();
        });
        QTRY_COMPARE_WITH_TIMEOUT(wifi.networks()->rowCount(), 3, 4000);
        QVERIFY(ticks >= 15);
        QVERIFY(!wrongThread);
        QCOMPARE(wifi.currentSsid(), QStringLiteral("Home"));
        QCOMPARE(row(wifi, 0, WifiNetworkModel::SsidRole).toString(), QStringLiteral("Home"));
        QCOMPARE(row(wifi, 0, WifiNetworkModel::SignalRole).toInt(), 85);
        QVERIFY(row(wifi, 0, WifiNetworkModel::SecureRole).toBool());
        QVERIFY(row(wifi, 0, WifiNetworkModel::ConnectedRole).toBool());
        QVERIFY(row(wifi, 0, WifiNetworkModel::SavedConnectionRole).toBool());
        QCOMPARE(counters().value("get").toInt(), 0);
        QCOMPARE(counters().value("apReads").toInt(), 4); // Active AP is reused.
        QCOMPARE(counters().value("savedReads").toInt(), 1);
        wifi.refreshNetworks();
        QTRY_COMPARE_WITH_TIMEOUT(counters().value("apReads").toInt(), 8, 4000);
        QCOMPARE(counters().value("savedReads").toInt(), 1); // Cached until settings change.
    }

    void repeatedRefreshesCoalesceAndPreserveScanRequest() {
        startService();
        configure({{"delay", 100}});
        WifiController wifi;
        QTRY_VERIFY(counters().value("apReads").toInt() >= 1);
        QElapsedTimer elapsed;
        elapsed.start();
        wifi.refreshNetworks(true);
        for (int i = 0; i < 30; ++i) wifi.refreshNetworks();
        QVERIFY(elapsed.elapsed() < 100);
        QTRY_COMPARE_WITH_TIMEOUT(wifi.networks()->rowCount(), 3, 4000);
        QCOMPARE(counters().value("scans").toInt(), 1);
        QVERIFY(counters().value("snapshots").toInt() <= 3);
    }

    void powerChangeDiscardsPendingSnapshot() {
        startService();
        WifiController wifi;
        QTRY_COMPARE(wifi.networks()->rowCount(), 3);
        configure({{"delay", 180}});
        const auto before = counters().value("apReads").toInt();
        wifi.refreshNetworks();
        QTRY_VERIFY(counters().value("apReads").toInt() > before);
        configure({{"enabled", false}});
        QTRY_VERIFY_WITH_TIMEOUT(!wifi.enabled(), 4000);
        QCOMPARE(wifi.networks()->rowCount(), 0);
        QTest::qWait(300);
        QVERIFY(!wifi.enabled());
        QCOMPARE(wifi.networks()->rowCount(), 0);
        QCOMPARE(wifi.currentSsid(), QString());
    }

    void failedRefreshKeepsLastListAndReportsError() {
        startService();
        WifiController wifi;
        QTRY_COMPARE(wifi.networks()->rowCount(), 3);
        configure({{"failList", true}});
        wifi.refreshNetworks();
        QTRY_VERIFY(wifi.errorMessage().contains("AP list unavailable"));
        QCOMPARE(wifi.networks()->rowCount(), 3);
        wifi.clearMessages();
        configure({{"failList", false}, {"delay", 1700}});
        wifi.refreshNetworks();
        QTRY_VERIFY_WITH_TIMEOUT(wifi.errorMessage().contains("timed out"), 4000);
        QCOMPARE(wifi.networks()->rowCount(), 3);
    }

    void iwdUsesManagedObjectSnapshot() {
        startService(true);
        configure({{"delay", 180}});
        WifiController wifi;
        QTRY_VERIFY2_WITH_TIMEOUT(wifi.networks()->rowCount() == 2,
            qPrintable(wifi.backendName() + ": " + wifi.errorMessage() + " "
                + QString::fromUtf8(QJsonDocument::fromVariant(counters()).toJson(QJsonDocument::Compact))
                + QString::fromUtf8(m_helper.readAllStandardError())), 4000);
        QCOMPARE(wifi.backendName(), QStringLiteral("iwd"));
        QVERIFY(wifi.enabled());
        QCOMPARE(wifi.currentSsid(), QStringLiteral("Home"));
        QVERIFY(row(wifi, 0, WifiNetworkModel::SavedConnectionRole).toBool());
        QVERIFY(row(wifi, 0, WifiNetworkModel::SecureRole).toBool());
        QVERIFY(!row(wifi, 1, WifiNetworkModel::SecureRole).toBool());
        QVERIFY(!row(wifi, 1, WifiNetworkModel::SavedConnectionRole).toBool());
        QCOMPARE(counters().value("get").toInt(), 0);
        QCOMPARE(counters().value("orderedReads").toInt(), 1);
        control("EmitNetworkAdded");
        QTRY_VERIFY(counters().value("orderedReads").toInt() > 1);
        QCOMPARE(wifi.currentSsid(), QStringLiteral("Home"));
    }

    void backendReplacementDiscardsPendingSnapshot_data() {
        QTest::addColumn<bool>("switchToIwd");
        QTest::newRow("switch-backend") << true;
        QTest::newRow("restart-networkmanager") << false;
    }

    void backendReplacementDiscardsPendingSnapshot() {
        QFETCH(bool, switchToIwd);
        startService();
        WifiController wifi;
        QTRY_COMPARE(wifi.networks()->rowCount(), 3);
        configure({{"delay", 300}});
        const auto before = counters().value("apReads").toInt();
        wifi.refreshNetworks();
        QTRY_VERIFY(counters().value("apReads").toInt() > before);
        m_helper.kill();
        QVERIFY(m_helper.waitForFinished(2000));
        startService(switchToIwd);
        const QString expectedBackend = switchToIwd ? QStringLiteral("iwd") : QStringLiteral("networkmanager");
        const int expectedRows = switchToIwd ? 2 : 3;
        QTRY_COMPARE_WITH_TIMEOUT(wifi.backendName(), expectedBackend, 4000);
        QTRY_COMPARE(wifi.networks()->rowCount(), expectedRows);
        QTRY_COMPARE_WITH_TIMEOUT(counters().value("snapshots").toInt(), 1, 4000);
        QTest::qWait(350);
        QCOMPARE(wifi.backendName(), expectedBackend);
        QCOMPARE(wifi.networks()->rowCount(), expectedRows);
        if (!switchToIwd)
            QCOMPARE(counters().value("savedReads").toInt(), 1);
    }

    void destructionDoesNotWaitForSlowService() {
        startService();
        configure({{"delay", 500}});
        auto wifi = std::make_unique<WifiController>();
        QTRY_VERIFY(counters().value("apReads").toInt() >= 1);
        QElapsedTimer elapsed;
        elapsed.start();
        wifi.reset();
        QVERIFY(elapsed.elapsed() < 100);
        QTest::qWait(600); // A late reply must not dereference the deleted controller.
    }
};

int main(int argc, char **argv) {
    if (qgetenv("TIDE_ISLAND_WIFI_TEST_ISOLATED") != "1" || qgetenv("DBUS_SESSION_BUS_ADDRESS").isEmpty()) {
        std::fprintf(stderr, "Run this test on an isolated bus via CTest.\n");
        return 1;
    }
    // Never access or mutate the machine's actual network service.
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", qgetenv("DBUS_SESSION_BUS_ADDRESS"));
    QCoreApplication app(argc, argv);
    qDBusRegisterMetaType<Paths>();
    qDBusRegisterMetaType<Settings>();
    qDBusRegisterMetaType<ManagedObjects>();
    qDBusRegisterMetaType<std::pair<QDBusObjectPath, qint16>>();
    qDBusRegisterMetaType<OrderedNetworks>();
    const auto args = app.arguments();
    if (args.contains("--fake-networkmanager") || args.contains("--fake-iwd")) {
        const bool iwd = args.contains("--fake-iwd");
        FakeWifiService service(iwd);
        auto bus = QDBusConnection::systemBus();
        if (!bus.registerService(iwd ? "net.connman.iwd" : nmService)
            || !bus.registerVirtualObject("/", &service, QDBusConnection::SubPath)) return 2;
        std::puts("ready");
        std::fflush(stdout);
        return app.exec();
    }
    WifiControllerTests tests;
    return QTest::qExec(&tests, argc, argv);
}

#include "wifi_controller_tests.moc"
