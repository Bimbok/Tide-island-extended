#include "SystemStats.h"

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QScopeGuard>
#include <QSemaphore>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QThread>
#include <QtTest>
#include <atomic>
#include <memory>

namespace {
SystemStats::Snapshot sample(int sequence = 1) {
    SystemStats::Snapshot result;
    result.cpuValid = true;
    result.cpuTotal = sequence == 1 ? 1000 : 1200;
    result.cpuIdle = sequence == 1 ? 600 : 650;
    result.ramUsage = 0.5;
    result.storageValid = true;
    result.bytesTotal = 1000;
    result.bytesFree = 400;
    result.bytesAvailable = 300;
    return result;
}
bool writeFile(const QString &path, const QByteArray &contents) {
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(contents) == contents.size();
}
struct Calls {
    std::atomic_int total {0};
    std::atomic_int stats {0};
    std::atomic_int storage {0};
};
}

// The real QML consumer is exercised without starting audio, D-Bus, battery,
// or recording monitors from the rest of the application.
class StubSysBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(int batteryCapacity READ batteryCapacity CONSTANT)
    Q_PROPERTY(QString batteryStatus READ batteryStatus CONSTANT)
public:
    int batteryCapacity() const { return -1; }
    QString batteryStatus() const { return {}; }
signals:
    void volumeChanged(int volume, bool muted);
    void batteryChanged(int capacity, const QString &status);
    void brightnessChanged(double value);
    void bluetoothChanged(bool connected);
};

class StubSystemServices : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList cavaLevels READ cavaLevels CONSTANT)
public:
    QVariantList cavaLevels() const { return {}; }
    Q_INVOKABLE void requestBrightness() {}
    Q_INVOKABLE void requestVolume() {}
    Q_INVOKABLE void setCavaClientActive(const QString &, bool) {}
signals:
    void brightnessSnapshotReady(double value, const QString &error);
    void volumeSnapshotReady(double value, bool muted, const QString &error);
    void cavaLevelsChanged();
};

class SystemStatsTests : public QObject {
    Q_OBJECT
private slots:
    void procSnapshotExcludesGuestTimeAndReadsAvailableMemory() {
        QTemporaryDir proc;
        QVERIFY(proc.isValid());
        QVERIFY(writeFile(proc.filePath("stat"), "cpu 100 10 30 500 20 5 5 10 80 5\ncpu0 1 2 3 4\n"));
        QVERIFY(writeFile(proc.filePath("meminfo"), "MemTotal: 1000 kB\nMemFree: 10 kB\nMemAvailable: 400 kB\n"));
        const auto result = SystemStats::readSnapshot(true, false, proc.path());
        QVERIFY2(result.statsError.isEmpty(), qPrintable(result.statsError));
        QVERIFY(result.cpuValid);
        QCOMPARE(result.cpuTotal, quint64(680));
        QCOMPARE(result.cpuIdle, quint64(520));
        QCOMPARE(result.ramUsage, 0.6);
        QVERIFY(!result.storageValid);

        QVERIFY(writeFile(proc.filePath("stat"), "cpu 1 nope 2 3 4\n"));
        QVERIFY(writeFile(proc.filePath("meminfo"), "MemTotal: 1000 kB\n"));
        const auto invalid = SystemStats::readSnapshot(true, false, proc.path());
        QVERIFY(!invalid.cpuValid);
        QCOMPARE(invalid.ramUsage, -1.0);
        QVERIFY(invalid.statsError.contains("CPU"));
        QVERIFY(invalid.statsError.contains("memory"));
    }

    void screensShareOneSampleAndCpuBaselineAndStopWhenHidden() {
        auto calls = std::make_shared<Calls>();
        SystemStats stats([calls](bool cpu, bool storage) {
            ++calls->total;
            if (storage) ++calls->storage;
            return sample(cpu ? ++calls->stats : 1);
        });
        bool wrongThread = false;
        connect(&stats, &SystemStats::statsChanged, this, [&]() {
            wrongThread |= QThread::currentThread() != stats.thread();
        });
        stats.refresh();
        QTest::qWait(30);
        QCOMPARE(calls->total.load(), 0);
        stats.setClientActive("screen-1", true, true);
        stats.setClientActive("screen-2", true, true);
        stats.setClientActive("screen-3", true, true);
        for (int i = 0; i < 50; ++i) stats.refresh();
        QTRY_COMPARE(stats.ramUsage(), 0.5);
        QTRY_COMPARE(stats.storageUsage(), 67.0);
        QCOMPARE(stats.cpuUsage(), -1.0); // The first reading is a baseline.
        QCOMPARE(calls->total.load(), 1);
        QTRY_COMPARE_WITH_TIMEOUT(stats.cpuUsage(), 0.75, 4000);
        QCOMPARE(calls->stats.load(), 2);
        for (int i = 0; i < 50; ++i) stats.refresh();
        QTest::qWait(50);
        QCOMPARE(calls->stats.load(), 2);
        QTRY_COMPARE_WITH_TIMEOUT(calls->stats.load(), 3, 4000);
        QTest::qWait(50);
        QCOMPARE(stats.cpuUsage(), 0.75); // No new ticks must not reset to zero.
        QVERIFY(!wrongThread);
        stats.setClientActive("screen-1", false, false);
        stats.setClientActive("screen-2", false, false);
        stats.setClientActive("screen-3", false, false);
        QTest::qWait(4300); // Beyond the next CPU and initial 10s storage tick.
        QCOMPARE(calls->total.load(), 3);
        QCOMPARE(calls->storage.load(), 1);
    }

    void slowSamplingIsResponsiveAndOldSubscriptionResultsAreDiscarded() {
        struct State { std::atomic_int calls {0}; QSemaphore gate; };
        auto state = std::make_shared<State>();
        const auto release = qScopeGuard([state]() { state->gate.release(); });
        SystemStats stats([state](bool, bool) {
            const int call = ++state->calls;
            if (call == 1) state->gate.acquire();
            auto result = sample();
            result.ramUsage = call == 1 ? 0.1 : 0.8;
            return result;
        });
        QSignalSpy changes(&stats, &SystemStats::statsChanged);
        stats.setClientActive("old-screen", true, true);
        QTRY_COMPARE(state->calls.load(), 1);
        int ticks = 0;
        QTimer heartbeat;
        connect(&heartbeat, &QTimer::timeout, this, [&ticks]() { ++ticks; });
        heartbeat.start(5);
        QTest::qWait(50);
        QVERIFY(ticks >= 3);
        stats.setClientActive("old-screen", false, false);
        stats.setClientActive("new-screen", true, true);
        for (int i = 0; i < 50; ++i) stats.refresh();
        state->gate.release();
        QTRY_COMPARE(stats.ramUsage(), 0.8);
        QCOMPARE(state->calls.load(), 2);
        QCOMPARE(changes.count(), 1);
        QCOMPARE(stats.cpuUsage(), -1.0);
    }

    void storageRetainsDfReservedBlockAndRoundingSemantics_data() {
        QTest::addColumn<qint64>("total");
        QTest::addColumn<qint64>("free");
        QTest::addColumn<qint64>("available");
        QTest::addColumn<double>("percent");
        QTest::newRow("reserved-blocks") << qint64(1000) << qint64(400) << qint64(300) << 67.0;
        QTest::newRow("no-reserved-blocks") << qint64(1000) << qint64(400) << qint64(400) << 60.0;
        QTest::newRow("round-up") << qint64(1000) << qint64(999) << qint64(900) << 1.0;
        QTest::newRow("full") << qint64(1000) << qint64(0) << qint64(0) << 100.0;
        QTest::newRow("empty") << qint64(1000) << qint64(1000) << qint64(1000) << 0.0;
        QTest::newRow("negative-available") << qint64(1000) << qint64(0) << qint64(-10) << 102.0;
    }

    void storageRetainsDfReservedBlockAndRoundingSemantics() {
        QFETCH(qint64, total);
        QFETCH(qint64, free);
        QFETCH(qint64, available);
        QFETCH(double, percent);
        SystemStats stats([=](bool, bool) {
            auto result = sample();
            result.bytesTotal = total;
            result.bytesFree = free;
            result.bytesAvailable = available;
            return result;
        });
        stats.setClientActive("screen", false, true);
        QTRY_COMPARE(stats.storageUsage(), percent);
        QCOMPARE(stats.cpuUsage(), -1.0);
        QCOMPARE(stats.ramUsage(), -1.0);
    }

    void failedSamplingPreservesLastValuesAndRecovers() {
        auto calls = std::make_shared<std::atomic_int>(0);
        SystemStats stats([calls](bool, bool) {
            if (++*calls == 2) {
                SystemStats::Snapshot failure;
                failure.statsError = "temporarily unavailable";
                return failure;
            }
            auto result = sample(calls->load());
            result.ramUsage = calls->load() >= 3 ? 0.6 : 0.5;
            return result;
        });
        stats.setClientActive("screen", true, false);
        QTRY_COMPARE(stats.ramUsage(), 0.5);
        QTRY_COMPARE_WITH_TIMEOUT(stats.statsError(), QStringLiteral("temporarily unavailable"), 4000);
        QCOMPARE(stats.ramUsage(), 0.5);
        QTRY_COMPARE_WITH_TIMEOUT(stats.ramUsage(), 0.6, 4000);
        QCOMPARE(stats.statsError(), QString());
        QCOMPARE(stats.cpuUsage(), 0.75);
    }

    void destructionDoesNotWaitForWorker() {
        struct State { std::atomic_bool started {false}; std::atomic_bool finished {false}; QSemaphore gate; };
        auto state = std::make_shared<State>();
        const auto release = qScopeGuard([state]() { state->gate.release(); });
        auto stats = std::make_unique<SystemStats>([state](bool, bool) {
            state->started = true;
            state->gate.acquire();
            state->finished = true;
            return sample();
        });
        stats->setClientActive("screen", true, false);
        QTRY_VERIFY(state->started.load());
        QElapsedTimer elapsed;
        elapsed.start();
        stats.reset();
        QVERIFY(elapsed.elapsed() < 100);
        state->gate.release();
        QTRY_VERIFY(state->finished.load());
    }

    void nativeStorageReaderMatchesDf() {
        const auto df = QStandardPaths::findExecutable(QStringLiteral("df"));
        if (df.isEmpty()) QSKIP("df is optional; fixture tests still verify the percentage calculation.");
        SystemStats stats;
        stats.setClientActive("screen", false, true);
        QTRY_VERIFY_WITH_TIMEOUT(stats.storageUsage() >= 0, 3000);
        QCOMPARE(stats.storageError(), QString());
        QProcess process;
        process.start(df, {"--output=pcent", "/"});
        QVERIFY(process.waitForFinished(2000));
        QCOMPARE(process.exitCode(), 0);
        const auto lines = process.readAllStandardOutput().trimmed().split('\n');
        QCOMPARE(lines.size(), 2);
        bool ok = false;
        const auto percent = lines.last().trimmed().chopped(1).toDouble(&ok);
        QVERIFY(ok);
        // Other processes may write between the two filesystem snapshots.
        QVERIFY(qAbs(stats.storageUsage() - percent) <= 1);
        QCOMPARE(stats.cpuUsage(), -1.0);
        QCOMPARE(stats.ramUsage(), -1.0);
    }

    void qmlConsumersSubscribeOnlyWhileTheirModulesAreVisible() {
        auto calls = std::make_shared<Calls>();
        SystemStats stats([calls](bool cpu, bool storage) {
            ++calls->total;
            if (storage) ++calls->storage;
            return sample(cpu ? ++calls->stats : 1);
        });
        StubSysBackend hardware;
        StubSystemServices services;
        qmlRegisterSingletonInstance("IslandBackend", 1, 0, "SystemStats", &stats);
        qmlRegisterSingletonInstance("IslandBackend", 1, 0, "SysBackend", &hardware);
        qmlRegisterSingletonInstance("IslandBackend", 1, 0, "SystemServices", &services);
        QTemporaryDir imports;
        QVERIFY(imports.isValid());
        QVERIFY(QDir().mkpath(imports.filePath("IslandBackend")));
        QVERIFY(writeFile(imports.filePath("IslandBackend/qmldir"), "module IslandBackend\n"));
        QQmlEngine engine;
        engine.addImportPath(imports.path());
        QQmlComponent component(&engine, QUrl::fromLocalFile(QStringLiteral(ISLAND_SYSTEM_STATE_SOURCE)));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        const QVariantMap initial {{"configuredLeftSwipeItems", QVariantList {"cpu", "ram", "storage"}}};
        std::unique_ptr<QObject> first(component.createWithInitialProperties(initial));
        std::unique_ptr<QObject> second(component.createWithInitialProperties(initial));
        QVERIFY(first && second);
        QTest::qWait(100);
        QCOMPARE(calls->total.load(), 0);
        QVERIFY(first->setProperty("customSwipeActive", true));
        QTRY_COMPARE(first->property("currentRamUsage").toDouble(), 0.5);
        QVERIFY(second->setProperty("customSwipeActive", true));
        QTest::qWait(100);
        QCOMPARE(calls->total.load(), 1);
        QCOMPARE(second->property("currentStorageUsage").toDouble(), 67.0);
        first.reset(); // Destroying one screen must keep the other's subscription.
        QTRY_COMPARE_WITH_TIMEOUT(second->property("currentCpuUsage").toDouble(), 0.75, 4000);
        QCOMPARE(calls->stats.load(), 2);
        QVERIFY(second->setProperty("statsVisible", false)); // Auto-hidden capsule.
        QTest::qWait(3300);
        QCOMPARE(calls->total.load(), 2);
        QVERIFY(second->setProperty("configuredLeftSwipeItems", QVariantList {"time"}));
        QVERIFY(second->setProperty("statsVisible", true));
        QTest::qWait(100);
        QCOMPARE(calls->total.load(), 2);
        second.reset();
    }
};

QTEST_MAIN(SystemStatsTests)
#include "system_stats_tests.moc"
