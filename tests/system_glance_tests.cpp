#include <QTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QFile>
#include "SystemGlanceBackend.h"

class SystemGlanceTests : public QObject {
    Q_OBJECT

    QTemporaryDir m_tempConfigDir;
    QByteArray m_origXdgConfig;

private slots:
    void initTestCase() {
        m_origXdgConfig = qgetenv("XDG_CONFIG_HOME");
        QVERIFY(m_tempConfigDir.isValid());
        qputenv("XDG_CONFIG_HOME", m_tempConfigDir.path().toLocal8Bit());
    }

    void cleanupTestCase() {
        if (!m_origXdgConfig.isEmpty()) {
            qputenv("XDG_CONFIG_HOME", m_origXdgConfig);
        } else {
            qunsetenv("XDG_CONFIG_HOME");
        }
    }

    void testFormattingHelpers() {
        // Speed formatting
        QCOMPARE(SystemGlanceBackend::formatSpeed(0), QStringLiteral("0 B/s"));
        QCOMPARE(SystemGlanceBackend::formatSpeed(512), QStringLiteral("512 B/s"));
        QCOMPARE(SystemGlanceBackend::formatSpeed(1024), QStringLiteral("1.0 KB/s"));
        QCOMPARE(SystemGlanceBackend::formatSpeed(1536), QStringLiteral("1.5 KB/s"));
        QCOMPARE(SystemGlanceBackend::formatSpeed(1024 * 1024), QStringLiteral("1.0 MB/s"));
        QCOMPARE(SystemGlanceBackend::formatSpeed(5.5 * 1024 * 1024), QStringLiteral("5.5 MB/s"));
        QCOMPARE(SystemGlanceBackend::formatSpeed(2.5 * 1024 * 1024 * 1024.0), QStringLiteral("2.50 GB/s"));

        // Uptime formatting
        QCOMPARE(SystemGlanceBackend::formatUptime(45), QStringLiteral("0m"));
        QCOMPARE(SystemGlanceBackend::formatUptime(120), QStringLiteral("2m"));
        QCOMPARE(SystemGlanceBackend::formatUptime(3600), QStringLiteral("1h 0m"));
        QCOMPARE(SystemGlanceBackend::formatUptime(3665), QStringLiteral("1h 1m"));
        QCOMPARE(SystemGlanceBackend::formatUptime(90000), QStringLiteral("1d 1h"));
    }

    void testOnDemandLifecycle() {
        SystemGlanceBackend glance;

        // Initially inactive, 0 timer activity
        QVERIFY(!glance.isActive());

        QSignalSpy activeSpy(&glance, &SystemGlanceBackend::activeChanged);
        QSignalSpy statsSpy(&glance, &SystemGlanceBackend::statsUpdated);

        // Activating glance starts sampling
        glance.setActive(true);
        QVERIFY(glance.isActive());
        QCOMPARE(activeSpy.count(), 1);
        QVERIFY(statsSpy.count() >= 1);

        // Verify metrics are populated
        QVERIFY(glance.memoryTotalGb() > 0.0);
        QVERIFY(glance.memoryUsagePercent() >= 0.0 && glance.memoryUsagePercent() <= 100.0);
        QVERIFY(!glance.memoryText().isEmpty());
        QVERIFY(glance.diskTotalGb() > 0.0);
        QVERIFY(!glance.diskText().isEmpty());
        QVERIFY(!glance.userName().isEmpty());
        QVERIFY(!glance.hostName().isEmpty());
        QVERIFY(!glance.osName().isEmpty());

        // Deactivating glance stops sampling
        glance.setActive(false);
        QVERIFY(!glance.isActive());
        QCOMPARE(activeSpy.count(), 2);
    }

    void testRefreshNow() {
        SystemGlanceBackend glance;
        QSignalSpy statsSpy(&glance, &SystemGlanceBackend::statsUpdated);

        glance.refreshNow();
        QCOMPARE(statsSpy.count(), 1);
        QVERIFY(glance.cpuUsage() >= 0.0 && glance.cpuUsage() <= 100.0);
        QVERIFY(!glance.downloadSpeedText().isEmpty());
        QVERIFY(!glance.uploadSpeedText().isEmpty());
    }

    void testAvatarSupport() {
        SystemGlanceBackend glance;
        QSignalSpy avatarSpy(&glance, &SystemGlanceBackend::avatarPathChanged);

        // Setting a custom avatar path using the isolated temporary config directory
        const QString testPath = m_tempConfigDir.filePath(QStringLiteral("test_avatar.png"));
        QFile file(testPath);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("dummy avatar data");
        file.close();

        glance.setAvatarPath(testPath);
        QCOMPARE(avatarSpy.count(), 1);
        QCOMPARE(glance.avatarPath(), QStringLiteral("file://") + testPath);
    }

    void testKernelAndBatteryTelemetry() {
        SystemGlanceBackend glance;
        QVERIFY(!glance.kernelVersion().isEmpty());
        QVERIFY(!glance.kernelRelease().isEmpty());
        QVERIFY(!glance.kernelArch().isEmpty());

        glance.refreshNow();
        QVERIFY(!glance.loadAvgText().isEmpty());
        QVERIFY(glance.totalTasks() >= 0);
        QVERIFY(!glance.cpuGovernor().isEmpty());

        if (glance.hasBattery()) {
            QVERIFY(glance.batteryCapacity() >= 0 && glance.batteryCapacity() <= 100);
            QVERIFY(!glance.batteryStatus().isEmpty());
            QVERIFY(!glance.batteryRateText().isEmpty());
            QVERIFY(glance.batteryHealthPercent() >= 0 && glance.batteryHealthPercent() <= 100);
        }
    }

    void testSwapAndUpdates() {
        SystemGlanceBackend glance;
        glance.refreshNow();

        if (glance.hasSwap()) {
            QVERIFY(glance.swapTotalGb() > 0.0);
            QVERIFY(glance.swapUsagePercent() >= 0.0 && glance.swapUsagePercent() <= 100.0);
            QVERIFY(!glance.swapText().isEmpty());
        }

        QSignalSpy spy(&glance, &SystemGlanceBackend::updatesChanged);
        glance.checkUpdatesAsync();
        QVERIFY(glance.checkingUpdates());
        QTRY_VERIFY_WITH_TIMEOUT(!glance.checkingUpdates(), 12000);
        qDebug() << "Pending updates count:" << glance.pendingUpdatesCount();
        QVERIFY(glance.pendingUpdatesCount() >= 0);
    }
};

QTEST_MAIN(SystemGlanceTests)
#include "system_glance_tests.moc"
