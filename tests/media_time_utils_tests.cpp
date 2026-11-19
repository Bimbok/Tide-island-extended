#include <QFile>
#include <QJSEngine>
#include <QJSValue>
#include <QtTest>

class MediaTimeUtilsTests : public QObject
{
    Q_OBJECT

private:
    QJSEngine m_engine;

    QJSValue call(const QString &name, const QJSValueList &arguments)
    {
        return m_engine.globalObject().property(name).call(arguments);
    }

private slots:
    void initTestCase()
    {
        QFile source(QStringLiteral(MEDIA_TIME_UTILS_SOURCE));
        QVERIFY2(source.open(QIODevice::ReadOnly | QIODevice::Text), qPrintable(source.errorString()));
        QString script = QString::fromUtf8(source.readAll());
        script.remove(QStringLiteral(".pragma library"));
        const QJSValue result = m_engine.evaluate(script, source.fileName());
        QVERIFY2(!result.isError(), qPrintable(result.toString()));
    }

    void testFormatTime()
    {
        QCOMPARE(call(QStringLiteral("formatTime"), {0}).toString(), QStringLiteral("0:00"));
        QCOMPARE(call(QStringLiteral("formatTime"), {-5}).toString(), QStringLiteral("0:00"));
        QCOMPARE(call(QStringLiteral("formatTime"), {45}).toString(), QStringLiteral("0:45"));
        QCOMPARE(call(QStringLiteral("formatTime"), {75}).toString(), QStringLiteral("1:15"));
        QCOMPARE(call(QStringLiteral("formatTime"), {3665}).toString(), QStringLiteral("61:05"));

        // Milliseconds support
        QCOMPARE(call(QStringLiteral("formatTime"), {45000}).toString(), QStringLiteral("0:45"));
        // Microseconds support
        QCOMPARE(call(QStringLiteral("formatTime"), {45000000}).toString(), QStringLiteral("0:45"));
    }

    void testToSeconds()
    {
        QCOMPARE(call(QStringLiteral("toSeconds"), {0}).toNumber(), 0.0);
        QCOMPARE(call(QStringLiteral("toSeconds"), {42}).toNumber(), 42.0);
        // Milliseconds (< 100,000,000)
        QCOMPARE(call(QStringLiteral("toSeconds"), {42000}).toNumber(), 42.0);
        // Microseconds (>= 100,000,000)
        QCOMPARE(call(QStringLiteral("toSeconds"), {420000000.0}).toNumber(), 420.0);
    }

    void testEstimatePosition()
    {
        // When not playing, position remains static at base
        const double basePos = 15.0;
        const double now = QDateTime::currentMSecsSinceEpoch();
        const double twoSecAgo = now - 2000.0;

        QCOMPARE(call(QStringLiteral("estimatePositionSec"), {
            basePos, twoSecAgo, 1.0, 100.0, false
        }).toNumber(), 15.0);

        // When playing, position advances by elapsed time (~2s)
        const double estimated = call(QStringLiteral("estimatePositionSec"), {
            basePos, twoSecAgo, 1.0, 100.0, true
        }).toNumber();
        QVERIFY(estimated >= 16.8 && estimated <= 17.5);

        // Clamping to total length
        const double clamped = call(QStringLiteral("estimatePositionSec"), {
            95.0, now - 10000.0, 1.0, 100.0, true
        }).toNumber();
        QCOMPARE(clamped, 100.0);
    }
};

QTEST_MAIN(MediaTimeUtilsTests)
#include "media_time_utils_tests.moc"
