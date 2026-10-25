#include "StyleTokensBackend.h"

#include <QColor>
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTemporaryFile>
#include <QtTest>

class StyleTokensBackendTests : public QObject
{
    Q_OBJECT

private slots:
    void testDefaultValues()
    {
        QTemporaryDir emptyDir;
        QVERIFY(emptyDir.isValid());
        qputenv("XDG_CONFIG_HOME", emptyDir.path().toLocal8Bit());

        StyleTokensBackend backend;
        backend.reload();

        // Verify default fixed colors
        QCOMPARE(backend.transparent(), QColor(Qt::transparent));
        QCOMPARE(backend.black(), QColor(Qt::black));
        QCOMPARE(backend.white(), QColor(Qt::white));

        // When no config file is loaded, defaults should be sleek dark theme
        // Default accent is #0a84ff
        QCOMPARE(backend.accent(), QColor("#0a84ff"));

        // Default battery colors
        QCOMPARE(backend.batteryCharging(), QColor("#34c759"));
        QCOMPARE(backend.batteryHigh(), QColor("#34c759"));
        QCOMPARE(backend.batteryMedium(), QColor("#ffcc00"));
        QCOMPARE(backend.batteryLow(), QColor("#ff9500"));
        QCOMPARE(backend.batteryCritical(), QColor("#ff3b30"));
        QCOMPARE(backend.batteryColor(80, false), QColor("#34c759"));
        QCOMPARE(backend.batteryColor(50, false), QColor("#ffcc00"));
        QCOMPARE(backend.batteryColor(20, false), QColor("#ff9500"));
        QCOMPARE(backend.batteryColor(10, false), QColor("#ff3b30"));
        QCOMPARE(backend.batteryColor(10, true), QColor("#34c759"));

        // Default card fill colors
        QCOMPARE(backend.cardFill(), QColor("#26272b"));
        QCOMPARE(backend.cardFillActive(), QColor("#26272b"));
        QCOMPARE(backend.cardFillHover(), QColor("#222327"));

        // Default radii and durations
        QCOMPARE(backend.radiusPanel(), 28);
        QCOMPARE(backend.radiusModule(), 20);
        QCOMPARE(backend.durationStandard(), 240);
        QCOMPARE(backend.surfaceBorder(), QColor("#26ffffff"));
        QCOMPARE(backend.surfaceHighlight(), QColor("#0cffffff"));
    }

    void testWithAlpha()
    {
        StyleTokensBackend backend;
        QColor red(255, 0, 0, 255);
        QColor translucentRed = backend.withAlpha(red, 0.5);
        QCOMPARE(translucentRed.red(), 255);
        QCOMPARE(translucentRed.alpha(), 128);
    }

    void testPaletteLoading()
    {
        QTemporaryDir tempDir;
        QVERIFY(tempDir.isValid());

        const QString colorsPath = tempDir.filePath(QStringLiteral("colors.json"));
        const QString userConfigPath = tempDir.filePath(QStringLiteral("userconfig.json"));

        // Write custom colors.json
        QFile colorsFile(colorsPath);
        QVERIFY(colorsFile.open(QIODevice::WriteOnly | QIODevice::Text));
        const char *colorsJson = R"({
            "colors": {
                "primary": "#ffb598",
                "on_primary": "#552008",
                "surface": "#1a110e",
                "surface_container_lowest": "#140c09",
                "surface_container_low": "#231a16",
                "surface_container": "#271e1a",
                "on_surface": "#f1dfd9",
                "on_surface_variant": "#d8c2ba",
                "outline": "#a08d86"
            }
        })";
        colorsFile.write(colorsJson);
        colorsFile.close();

        // Write userconfig.json pointing to this custom colors file
        QFile userConfigFile(userConfigPath);
        QVERIFY(userConfigFile.open(QIODevice::WriteOnly | QIODevice::Text));
        const QString userConfigJson = QString(R"({
            "colorPaletteEnabled": true,
            "colorsFilePath": "%1"
        })").arg(colorsPath);
        userConfigFile.write(userConfigJson.toUtf8());
        userConfigFile.close();

        // Set XDG_CONFIG_HOME to tempDir so StyleTokensBackend picks it up
        qputenv("XDG_CONFIG_HOME", tempDir.path().toLocal8Bit());

        // Create ~/.config/tide-island/ symlink or directory structure in tempDir
        QDir tideDir(tempDir.path() + QStringLiteral("/tide-island"));
        QVERIFY(tideDir.mkpath(QStringLiteral(".")));

        // Copy userconfig.json to tempDir/tide-island/userconfig.json
        QFile::copy(userConfigPath, tideDir.filePath(QStringLiteral("userconfig.json")));

        StyleTokensBackend backend;
        backend.reload();

        QVERIFY(backend.paletteLoaded());
        QCOMPARE(backend.colorsFilePath(), colorsPath);

        // Verify primary mapped to accent
        QCOMPARE(backend.accent(), QColor("#ffb598"));

        // Verify on_primary mapped to textOnAccent
        QCOMPARE(backend.textOnAccent(), QColor("#552008"));

        // Verify surface_container_lowest mapped to panel
        QCOMPARE(backend.panel(), QColor("#140c09"));

        // Verify surface_container_low mapped to module
        QCOMPARE(backend.module(), QColor("#231a16"));

        // Verify on_surface mapped to textPrimary
        QCOMPARE(backend.textPrimary(), QColor("#f1dfd9"));

        // Verify primary and on_primary mapped to batteryHigh and textOnBatteryHigh
        QCOMPARE(backend.batteryHigh(), QColor("#ffb598"));
        QCOMPARE(backend.textOnBatteryHigh(), QColor("#552008"));
        QCOMPARE(backend.batteryCharging(), QColor("#ffb598"));
        QCOMPARE(backend.textOnBatteryCharging(), QColor("#552008"));
        // Verify surface_container mapped to cardFill and cardFillActive
        QCOMPARE(backend.cardFill(), QColor("#271e1a"));
        QCOMPARE(backend.cardFillActive(), QColor("#271e1a"));
    }

    void testPaletteDisable()
    {
        QTemporaryDir tempDir;
        QVERIFY(tempDir.isValid());

        qputenv("XDG_CONFIG_HOME", tempDir.path().toLocal8Bit());
        QDir tideDir(tempDir.path() + QStringLiteral("/tide-island"));
        QVERIFY(tideDir.mkpath(QStringLiteral(".")));

        // Create userconfig with colorPaletteEnabled = false
        QFile userConfigFile(tideDir.filePath(QStringLiteral("userconfig.json")));
        QVERIFY(userConfigFile.open(QIODevice::WriteOnly | QIODevice::Text));
        userConfigFile.write(R"({ "colorPaletteEnabled": false })");
        userConfigFile.close();

        StyleTokensBackend backend;
        backend.reload();

        QCOMPARE(backend.paletteLoaded(), false);
        // Accent should revert to default #0a84ff
        QCOMPARE(backend.accent(), QColor("#0a84ff"));
        // Battery colors should revert to default
        QCOMPARE(backend.batteryHigh(), QColor("#34c759"));
        QCOMPARE(backend.textOnBatteryHigh(), QColor(Qt::black));
    }
};

QTEST_MAIN(StyleTokensBackendTests)
#include "style_tokens_backend_tests.moc"
