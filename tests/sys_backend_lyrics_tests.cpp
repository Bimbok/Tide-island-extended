#include "SysBackend.h"

#include <QtTest>
#include <QSignalSpy>
#include <QProcess>

class SysBackendLyricsTests : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() {
        // Use a standard persistent process for testing process lifecycle
        qputenv("QUICKSHELL_LYRICS_BACKEND", "/bin/cat");
    }

    void cleanupTestCase() {
        qunsetenv("QUICKSHELL_LYRICS_BACKEND");
    }

    void testInitialState() {
        SysBackend backend;
        QCOMPARE(backend.lyricsClientCount(), 0);
        QCOMPARE(backend.isLyricsIdleTimerActive(), false);
        QCOMPARE(backend.lyricsBackendStatus(), QStringLiteral("idle"));
    }

    void testLifecycleGracePeriodAndImmediateStop() {
        SysBackend backend;

        // 1. Activate client - should start the process
        backend.setLyricsClientActive(QStringLiteral("test-client-1"), true);
        QCOMPARE(backend.lyricsClientCount(), 1);
        QCOMPARE(backend.isLyricsIdleTimerActive(), false);

        // Wait for process to run
        QTRY_VERIFY_WITH_TIMEOUT(backend.lyricsBackendStatus() == QStringLiteral("running"), 2000);

        // 2. Add second client
        backend.setLyricsClientActive(QStringLiteral("test-client-2"), true);
        QCOMPARE(backend.lyricsClientCount(), 2);
        QCOMPARE(backend.isLyricsIdleTimerActive(), false);

        // 3. Remove one client - remaining client keeps it active, no idle timer
        backend.setLyricsClientActive(QStringLiteral("test-client-1"), false);
        QCOMPARE(backend.lyricsClientCount(), 1);
        QCOMPARE(backend.isLyricsIdleTimerActive(), false);

        // 4. Remove last client with grace period (immediate = false)
        backend.setLyricsClientActive(QStringLiteral("test-client-2"), false, false);
        QCOMPARE(backend.lyricsClientCount(), 0);
        // Idle grace timer must be running while keeping process alive
        QVERIFY(backend.isLyricsIdleTimerActive());

        // 5. Re-activate before grace timer expires
        backend.setLyricsClientActive(QStringLiteral("test-client-1"), true);
        QCOMPARE(backend.lyricsClientCount(), 1);
        // Grace timer should be cancelled immediately
        QCOMPARE(backend.isLyricsIdleTimerActive(), false);

        // 6. Immediate stop requested (e.g. music stopped or player closed)
        backend.setLyricsClientActive(QStringLiteral("test-client-1"), false, true);
        QCOMPARE(backend.lyricsClientCount(), 0);
        QCOMPARE(backend.isLyricsIdleTimerActive(), false);
        QTRY_VERIFY_WITH_TIMEOUT(backend.lyricsBackendStatus() == QStringLiteral("idle"), 1000);
    }
};

QTEST_MAIN(SysBackendLyricsTests)
#include "sys_backend_lyrics_tests.moc"
