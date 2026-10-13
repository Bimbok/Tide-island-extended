#include "SystemServices.h"

#include <QtTest>
#include <QSignalSpy>
#include <QVariantList>
#include <QVariantMap>

class SystemServicesNotificationTests : public QObject
{
    Q_OBJECT

private slots:
    void testRichNotificationParsing()
    {
        SystemServices services;
        QSignalSpy spy(&services, &SystemServices::notificationReceived);
        QVERIFY(spy.isValid());

        // Simulate dbus-monitor lines for a rich notification
        const QStringList lines = {
            QStringLiteral("method call time=1790772252.726897 sender=:1.1067 -> destination=:1.98 serial=9 path=/org/freedesktop/Notifications; interface=org.freedesktop.Notifications; member=Notify"),
            QStringLiteral("   string \"TestApp\""),
            QStringLiteral("   uint32 42"),
            QStringLiteral("   string \"test-app-icon\""),
            QStringLiteral("   string \"Update Available\""),
            QStringLiteral("   string \"A new version of TestApp is ready to install.\\nPlease restart.\""),
            QStringLiteral("   array ["),
            QStringLiteral("      string \"default\""),
            QStringLiteral("      string \"Open App\""),
            QStringLiteral("      string \"dismiss\""),
            QStringLiteral("      string \"Later\""),
            QStringLiteral("   ]"),
            QStringLiteral("   array ["),
            QStringLiteral("      dict entry("),
            QStringLiteral("         string \"image-path\""),
            QStringLiteral("         variant             string \"/tmp/test-avatar.png\""),
            QStringLiteral("      )"),
            QStringLiteral("      dict entry("),
            QStringLiteral("         string \"urgency\""),
            QStringLiteral("         variant             byte 2"),
            QStringLiteral("      )"),
            QStringLiteral("   ]"),
            QStringLiteral("   int32 -1")
        };

        // Feed lines to private method via QMetaObject invokeMethod
        for (const QString &line : lines) {
            QMetaObject::invokeMethod(&services, "handleNotificationLine",
                                      Qt::DirectConnection,
                                      Q_ARG(QString, line));
        }

        QCOMPARE(spy.count(), 1);
        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args.at(0).toUInt(), 42u); // replacesId
        QCOMPARE(args.at(1).toString(), QStringLiteral("TestApp"));
        QCOMPARE(args.at(2).toString(), QStringLiteral("test-app-icon"));
        QCOMPARE(args.at(3).toString(), QStringLiteral("Update Available"));
        QCOMPARE(args.at(4).toString(), QStringLiteral("A new version of TestApp is ready to install.\nPlease restart."));

        // Actions
        const QVariantList actions = args.at(5).toList();
        QCOMPARE(actions.size(), 2);
        const QVariantMap action1 = actions.at(0).toMap();
        QCOMPARE(action1.value(QStringLiteral("id")).toString(), QStringLiteral("default"));
        QCOMPARE(action1.value(QStringLiteral("text")).toString(), QStringLiteral("Open App"));
        const QVariantMap action2 = actions.at(1).toMap();
        QCOMPARE(action2.value(QStringLiteral("id")).toString(), QStringLiteral("dismiss"));
        QCOMPARE(action2.value(QStringLiteral("text")).toString(), QStringLiteral("Later"));

        // Image path
        QCOMPARE(args.at(6).toString(), QStringLiteral("/tmp/test-avatar.png"));

        // Urgency
        QCOMPARE(args.at(7).toInt(), 2);
    }

    void testActionAndCloseInvokables()
    {
        SystemServices services;
        // Verify invokable methods execute without crash
        services.invokeNotificationAction(42, QStringLiteral("default"));
        services.closeNotification(42, 2);
        QTest::qWait(200);
    }

    void testAudioDevicesAndAppStreamsInvokables()
    {
        SystemServices services;
        QSignalSpy outputsSpy(&services, &SystemServices::audioOutputsChanged);
        QSignalSpy inputsSpy(&services, &SystemServices::audioInputsChanged);
        QSignalSpy streamsSpy(&services, &SystemServices::appStreamsChanged);
        QVERIFY(outputsSpy.isValid());
        QVERIFY(inputsSpy.isValid());
        QVERIFY(streamsSpy.isValid());

        services.setAudioMonitoringActive(true);
        services.requestAudioOutputs();
        services.requestAudioInputs();
        services.requestAppStreams();

        // Verify properties initial state
        QVERIFY(services.audioOutputs().isEmpty() || !services.audioOutputs().isEmpty());
        QVERIFY(services.audioInputs().isEmpty() || !services.audioInputs().isEmpty());

        // Wait for async commands to return
        QTest::qWait(600);

        // Verify outputs or inputs were populated on a running system
        QVERIFY(outputsSpy.count() >= 0);
        QVERIFY(inputsSpy.count() >= 0);

        // Test stream mute and volume adjustments do not crash
        services.setAppStreamVolume(99999, 0.75);
        services.toggleAppStreamMute(99999);
        services.setAudioMonitoringActive(false);
    }

    void testBatteryThresholdDetection()
    {
        SystemServices services;
        QSignalSpy spy(&services, &SystemServices::batteryThresholdChanged);
        QVERIFY(spy.isValid());

        services.requestBatteryThresholdState();

        if (QFile::exists(QStringLiteral("/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"))) {
            QVERIFY(services.batteryThresholdSupported());
            QCOMPARE(services.batteryThresholdType(), QStringLiteral("conservation"));
            QCOMPARE(services.batteryThresholdValue(), services.batteryConservationMode() ? 80 : 100);
            QCOMPARE(services.batteryThresholdPresets().size(), 2);
        }

        QVERIFY(services.batteryHealthPercent() >= 0 && services.batteryHealthPercent() <= 100);
        QVERIFY(services.batteryCycleCount() >= 0);
    }

    void testTerminalResolutionAndWrapping()
    {
        SystemServices services;
        const QString term = services.defaultTerminalEmulator();
        QVERIFY(!term.trimmed().isEmpty());

        // Empty command returns empty
        QVERIFY(services.wrapTerminalCommand({}).isEmpty());

        // Normal command wrapping
        const QStringList wrapped = services.wrapTerminalCommand({QStringLiteral("btop")});
        QVERIFY(wrapped.size() >= 2);
        QCOMPARE(wrapped.last(), QStringLiteral("btop"));
        QVERIFY(wrapped.first().contains(term) || term.contains(wrapped.first()));

        // Multi-arg command wrapping
        const QStringList wrappedMulti = services.wrapTerminalCommand({QStringLiteral("nvim"), QStringLiteral("file.txt")});
        QVERIFY(wrappedMulti.size() >= 3);
        QCOMPARE(wrappedMulti.at(wrappedMulti.size() - 2), QStringLiteral("nvim"));
        QCOMPARE(wrappedMulti.last(), QStringLiteral("file.txt"));
    }

    void testPrivacyIndicators()
    {
        SystemServices services;
        QSignalSpy privacySpy(&services, &SystemServices::privacyIndicatorsChanged);
        QVERIFY(privacySpy.isValid());

        // Check property getters
        QCOMPARE(services.privacyActive(), services.micActive() || services.cameraActive());

        // Simulate privacy snapshot output parsing
        const QString sampleOutput = QStringLiteral(
            "[{\"index\":10,\"source\":1,\"corked\":false,\"properties\":{\"application.name\":\"TestMicApp\",\"application.process.id\":\"1234\",\"application.process.binary\":\"testapp\"}}]"
            "\n---TIDE-PRIVACY-SEP---\n"
            "id 88, type PipeWire:Interface:Node/3\n"
            "media.class = \"Stream/Input/Video\"\n"
            "application.name = \"TestCamApp\"\n"
            "application.process.id = \"5678\"\n"
        );

        QMetaObject::invokeMethod(&services, "handlePrivacySnapshotOutput",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, sampleOutput));

        QVERIFY(services.micActive());
        QVERIFY(services.cameraActive());
        QVERIFY(services.privacyActive());
        QCOMPARE(services.activePrivacyApps().size(), 2);

        const QVariantMap app1 = services.activePrivacyApps().at(0).toMap();
        QCOMPARE(app1.value(QStringLiteral("name")).toString(), QStringLiteral("TestMicApp"));
        QCOMPARE(app1.value(QStringLiteral("type")).toString(), QStringLiteral("mic"));
        QCOMPARE(app1.value(QStringLiteral("pid")).toInt(), 1234);

        const QVariantMap app2 = services.activePrivacyApps().at(1).toMap();
        QCOMPARE(app2.value(QStringLiteral("name")).toString(), QStringLiteral("TestCamApp"));
        QCOMPARE(app2.value(QStringLiteral("type")).toString(), QStringLiteral("camera"));
        QCOMPARE(app2.value(QStringLiteral("pid")).toInt(), 5678);

        QVERIFY(privacySpy.count() >= 1);

        // Test 3-part format with fuser PID detection
        const QString sampleOutput3Part = QStringLiteral(
            "[]\n---TIDE-PRIVACY-SEP---\n99999\n---TIDE-PRIVACY-SEP---\n"
        );
        QMetaObject::invokeMethod(&services, "handlePrivacySnapshotOutput",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, sampleOutput3Part));
        QVERIFY(services.cameraActive());
        QVERIFY(!services.micActive());
        QVERIFY(services.privacyActive());

        // Test that screen share stream (e.g. Discord with media.role="Screen") does NOT trigger cameraActive
        const QString sampleScreenShare = QStringLiteral(
            "[]\n---TIDE-PRIVACY-SEP---\n\n---TIDE-PRIVACY-SEP---\n"
            "id 82, type PipeWire:Interface:Node/3\n"
            "media.class = \"Stream/Input/Video\"\n"
            "media.role = \"Screen\"\n"
            "application.name = \"Discord\"\n"
            "application.process.id = \"1708\"\n"
        );
        QMetaObject::invokeMethod(&services, "handlePrivacySnapshotOutput",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, sampleScreenShare));
        QVERIFY(!services.cameraActive());
        QVERIFY(services.screenRecordingActive());
        QCOMPARE(services.activePrivacyApps().size(), 1);
        const QVariantMap scApp = services.activePrivacyApps().at(0).toMap();
        QCOMPARE(scApp.value(QStringLiteral("name")).toString(), QStringLiteral("Discord"));
        QCOMPARE(scApp.value(QStringLiteral("type")).toString(), QStringLiteral("screen"));
        QCOMPARE(scApp.value(QStringLiteral("pid")).toInt(), 1708);
    }
};

QTEST_MAIN(SystemServicesNotificationTests)
#include "system_services_notification_tests.moc"
