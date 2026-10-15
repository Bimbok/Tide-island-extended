#include <QTest>
#include <QSignalSpy>
#include "SystemGlanceBackend.h"

class SystemGlanceTests : public QObject {
    Q_OBJECT

private slots:
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
};

QTEST_MAIN(SystemGlanceTests)
#include "system_glance_tests.moc"
