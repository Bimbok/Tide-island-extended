#include <QTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <memory>
#include "ScreenRecorderController.h"

class ScreenRecorderTests : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void testInitialState();
    void testTimeFormatting();
    void testPropertySetters();
    void testIdleZeroPolling();

private:
    std::unique_ptr<QTemporaryDir> m_tempDir;
};

void ScreenRecorderTests::initTestCase() {
    m_tempDir = std::make_unique<QTemporaryDir>();
    QVERIFY(m_tempDir->isValid());
    qputenv("XDG_RUNTIME_DIR", m_tempDir->path().toUtf8());
}

void ScreenRecorderTests::testInitialState() {
    ScreenRecorderController controller;
    QCOMPARE(ScreenRecorderController::instance(), &controller);
    QCOMPARE(controller.isRecording(), false);
    QCOMPARE(controller.isPaused(), false);
    QCOMPARE(controller.isReplayActive(), false);
    QCOMPARE(controller.recordingSeconds(), 0);
    QCOMPARE(controller.recordingTimeFormatted(), QStringLiteral("00:00"));
    QCOMPARE(controller.fps(), 60);
    QCOMPARE(controller.replaySeconds(), 60);
}

void ScreenRecorderTests::testTimeFormatting() {
    ScreenRecorderController controller;
    QCOMPARE(controller.recordingTimeFormatted(), QStringLiteral("00:00"));
}

void ScreenRecorderTests::testPropertySetters() {
    ScreenRecorderController controller;

    QSignalSpy micSpy(&controller, &ScreenRecorderController::micEnabledChanged);
    controller.setMicEnabled(true);
    QCOMPARE(controller.micEnabled(), true);
    QCOMPARE(micSpy.count(), 1);

    QSignalSpy fpsSpy(&controller, &ScreenRecorderController::fpsChanged);
    controller.setFps(120);
    QCOMPARE(controller.fps(), 120);
    QCOMPARE(fpsSpy.count(), 1);

    QSignalSpy replaySpy(&controller, &ScreenRecorderController::replaySecondsChanged);
    controller.setReplaySeconds(30);
    QCOMPARE(controller.replaySeconds(), 30);
    QCOMPARE(replaySpy.count(), 1);

    QSignalSpy screenSpy(&controller, &ScreenRecorderController::screenNameChanged);
    controller.setScreenName(QStringLiteral("DP-1"));
    QCOMPARE(controller.screenName(), QStringLiteral("DP-1"));
    QCOMPARE(screenSpy.count(), 1);
}

void ScreenRecorderTests::testIdleZeroPolling() {
    ScreenRecorderController controller;
    QCOMPARE(controller.isPollTimerActive(), false);
}

QTEST_MAIN(ScreenRecorderTests)
#include "screen_recorder_tests.moc"
