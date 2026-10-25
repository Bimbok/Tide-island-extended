#include "UserConfigBackend.h"
#include "../Tide-island-app/backend.hpp"
#include "../common/JsonComments.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QtTest>

namespace {
bool writeConfig(const QString &home, const QByteArray &contents) {
    if (!QDir().mkpath(home + "/tide-island")) return false;
    QFile file(home + "/tide-island/userconfig.json");
    return file.open(QIODevice::WriteOnly) && file.write(contents) == contents.size();
}
}

class UserConfigBackendTests : public QObject {
    Q_OBJECT
private slots:
    void blurDefaultsAndLiveReloadPreserveOpacity() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        qputenv("XDG_CONFIG_HOME", directory.path().toUtf8());
        QVERIFY(writeConfig(directory.path(), "{}"));
        UserConfigBackend runtime;
        QVERIFY(runtime.islandBlurEnabled());
        QCOMPARE(runtime.islandBackgroundOpacity(), 60);
        QSignalSpy changed(&runtime, &UserConfigBackend::islandBlurEnabledChanged);

        Backend settings;
        auto config = settings.userConfig();
        config.insert("islandBlurEnabled", false);
        config.insert("islandBackgroundOpacity", 60);
        QVERIFY(settings.save(config));
        runtime.reload();
        QVERIFY(!runtime.islandBlurEnabled());
        QCOMPARE(runtime.islandBackgroundOpacity(), 60);
        QCOMPARE(changed.count(), 1);

        config.insert("islandBlurEnabled", true);
        QVERIFY(settings.save(config));
        runtime.reload();
        QVERIFY(runtime.islandBlurEnabled());
        QCOMPARE(runtime.islandBackgroundOpacity(), 60);
        QCOMPARE(changed.count(), 2);

        QVERIFY(writeConfig(directory.path(), "{\"islandBlurEnabled\":\"false\"}"));
        runtime.reload();
        QVERIFY(runtime.islandBlurEnabled());
    }

    void stringsAndCommentsMatchAcrossBothConsumers_data() {
        QTest::addColumn<QByteArray>("input");
        QTest::addColumn<QString>("command");
        QTest::newRow("literal-block-comment")
            << QByteArray(R"json({"wallpaperCustomCommand":"printf '/*literal*/'"})json")
            << QStringLiteral("printf '/*literal*/'");
        QTest::newRow("even-backslashes-before-quote")
            << QByteArray("{\"wallpaperCustomCommand\":\"C:\\\\\", // real comment\r\n\"wallpaperPath\":\"https://example.com/a/*b*/\"}")
            << QStringLiteral("C:\\");
        for (const auto &command : {QStringLiteral("printf \"quoted // /* text */\""),
                                   QStringLiteral("\\\\\"// still a string /* */\\\\"),
                                   QStringLiteral("第一行\n第二行\t/*文字*/ https://example.com/😀")}) {
            auto input = QJsonDocument(QJsonObject {{"wallpaperCustomCommand", command}}).toJson();
            input.prepend("/* heading\r\n comment */\r\n// line comment\r\n");
            input.append("// trailing comment without newline");
            QTest::newRow(qPrintable(command)) << input << command;
        }
    }

    void stringsAndCommentsMatchAcrossBothConsumers() {
        QFETCH(QByteArray, input);
        QFETCH(QString, command);
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        qputenv("XDG_CONFIG_HOME", directory.path().toUtf8());
        QVERIFY(writeConfig(directory.path(), input));

        UserConfigBackend runtime;
        Backend settings;
        QVERIFY2(runtime.configError().isEmpty(), qPrintable(runtime.configError()));
        QVERIFY2(settings.errorString().isEmpty(), qPrintable(settings.errorString()));
        QCOMPARE(runtime.wallpaperCustomCommand(), command);
        QCOMPARE(settings.userConfig().value("wallpaperCustomCommand").toString(), command);

        // A settings save and live runtime reload must retain the same bytes.
        QVERIFY(settings.save(settings.userConfig()));
        runtime.reload();
        QCOMPARE(runtime.configError(), QString());
        QCOMPARE(runtime.wallpaperCustomCommand(), command);
    }

    void commentMaskPreservesStringsWhitespaceAndByteOffsets() {
        const QByteArray input = "// hi\r\n{\"v\":\"/*文字*/ //\",/*\r\n字*/\"n\":1}\n";
        const auto output = JsonComments::strip(input);
        QCOMPARE(output.size(), input.size());
        for (qsizetype i = 0; i < input.size(); ++i) {
            if (input[i] == '\r' || input[i] == '\n') QCOMPARE(output[i], input[i]);
        }
        QVERIFY(output.startsWith("     \r\n"));
        QVERIFY(output.contains("\"/*文字*/ //\""));
        QJsonParseError error;
        const auto document = QJsonDocument::fromJson(output, &error);
        QCOMPARE(error.error, QJsonParseError::NoError);
        QCOMPARE(document.object().value("v").toString(), QStringLiteral("/*文字*/ //"));

        // Removing the comment entirely would silently change 1/*...*/2 to 12.
        const auto invalid = JsonComments::strip("{\"n\":1/* comment */2}");
        QJsonDocument::fromJson(invalid, &error);
        QVERIFY(error.error != QJsonParseError::NoError);
    }

    void malformedJsonReportsTheSameOriginalByteOffset() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        qputenv("XDG_CONFIG_HOME", directory.path().toUtf8());
        const QByteArray input = "/* 注释\r\n保留位置 */\r\n{\"wallpaperCustomCommand\": #}\r\n";
        QVERIFY(writeConfig(directory.path(), input));
        UserConfigBackend runtime;
        Backend settings;
        QVERIFY(!runtime.configError().isEmpty());
        QVERIFY(!settings.errorString().isEmpty());
        QCOMPARE(runtime.configError(), settings.errorString());
        QVERIFY2(runtime.configError().contains(QStringLiteral("offset %1:").arg(input.indexOf('#'))),
                 qPrintable(runtime.configError()));
        QCOMPARE(runtime.wallpaperCustomCommand(), QString());
    }
};

QTEST_GUILESS_MAIN(UserConfigBackendTests)
#include "user_config_backend_tests.moc"
