#include <QFile>
#include <QJSEngine>
#include <QJSValue>
#include <QtTest>

class SpotlightTests : public QObject
{
    Q_OBJECT

private:
    QJSEngine m_engine;

    void loadScript(const QString &filePath)
    {
        QFile source(filePath);
        QVERIFY2(source.open(QIODevice::ReadOnly | QIODevice::Text), qPrintable(source.errorString()));
        QString script = QString::fromUtf8(source.readAll());
        script.remove(QStringLiteral(".pragma library"));
        const QJSValue result = m_engine.evaluate(script, source.fileName());
        QVERIFY2(!result.isError(), qPrintable(result.toString()));
    }

private slots:
    void initTestCase()
    {
        loadScript(QStringLiteral(SPOTLIGHT_CALC_SOURCE));
        loadScript(QStringLiteral(SPOTLIGHT_MATCH_SOURCE));
        loadScript(QStringLiteral(SPOTLIGHT_WEB_SOURCE));
        loadScript(QStringLiteral(SPOTLIGHT_FRECENCY_SOURCE));
        loadScript(QStringLiteral(DESKTOP_APP_LAUNCHER_SOURCE));
    }

    void testCalcArithmetic()
    {
        const QJSValue answerFn = m_engine.globalObject().property(QStringLiteral("answer"));
        QVERIFY(answerFn.isCallable());

        QJSValue res = answerFn.call({QStringLiteral("2 + 2 * 3")});
        QVERIFY(res.isObject());
        QCOMPARE(res.property(QStringLiteral("kind")).toString(), QStringLiteral("calc"));
        QCOMPARE(res.property(QStringLiteral("value")).toNumber(), 8.0);
        QCOMPARE(res.property(QStringLiteral("text")).toString(), QStringLiteral("8"));

        QJSValue sqrtRes = answerFn.call({QStringLiteral("sqrt(144)")});
        QVERIFY(sqrtRes.isObject());
        QCOMPARE(sqrtRes.property(QStringLiteral("value")).toNumber(), 12.0);

        QJSValue percentRes = answerFn.call({QStringLiteral("25% of 80")});
        QVERIFY(percentRes.isObject());
        QCOMPARE(percentRes.property(QStringLiteral("value")).toNumber(), 20.0);

        QJSValue hexRes = answerFn.call({QStringLiteral("0xff + 1")});
        QVERIFY(hexRes.isObject());
        QCOMPARE(hexRes.property(QStringLiteral("value")).toNumber(), 256.0);
    }

    void testCalcUnitConversions()
    {
        const QJSValue answerFn = m_engine.globalObject().property(QStringLiteral("answer"));
        QVERIFY(answerFn.isCallable());

        QJSValue convertRes = answerFn.call({QStringLiteral("10 km to mi")});
        QVERIFY(convertRes.isObject());
        QCOMPARE(convertRes.property(QStringLiteral("kind")).toString(), QStringLiteral("convert"));
        QVERIFY(convertRes.property(QStringLiteral("text")).toString().contains(QStringLiteral("mi")));

        QJSValue nonCalc = answerFn.call({QStringLiteral("firefox")});
        QVERIFY(nonCalc.isNull());
    }

    void testFuzzyMatch()
    {
        const QJSValue scoreFn = m_engine.globalObject().property(QStringLiteral("score"));
        QVERIFY(scoreFn.isCallable());

        const double exactScore = scoreFn.call({QStringLiteral("firefox"), QStringLiteral("Firefox")}).toNumber();
        QCOMPARE(exactScore, 1000.0);

        const double prefixScore = scoreFn.call({QStringLiteral("fire"), QStringLiteral("Firefox")}).toNumber();
        QVERIFY(prefixScore > 800.0);

        const double chunkScore = scoreFn.call({QStringLiteral("vsc"), QStringLiteral("Visual Studio Code")}).toNumber();
        QVERIFY(chunkScore > 500.0);

        const double noMatchScore = scoreFn.call({QStringLiteral("xyz"), QStringLiteral("Firefox")}).toNumber();
        QCOMPARE(noMatchScore, 0.0);
    }

    void testWebAddressDetection()
    {
        const QJSValue addressUrlFn = m_engine.globalObject().property(QStringLiteral("addressUrl"));
        QVERIFY(addressUrlFn.isCallable());

        QCOMPARE(addressUrlFn.call({QStringLiteral("github.com/Bimbok")}).toString(), QStringLiteral("https://github.com/Bimbok"));
        QCOMPARE(addressUrlFn.call({QStringLiteral("localhost:8080")}).toString(), QStringLiteral("http://localhost:8080"));
        QCOMPARE(addressUrlFn.call({QStringLiteral("just a search query")}).toString(), QStringLiteral(""));
    }

    void testFrecencyLearning()
    {
        const QJSValue emptyFn = m_engine.globalObject().property(QStringLiteral("empty"));
        const QJSValue recordFn = m_engine.globalObject().property(QStringLiteral("record"));
        const QJSValue boostFn = m_engine.globalObject().property(QStringLiteral("boost"));

        QVERIFY(emptyFn.isCallable());
        QVERIFY(recordFn.isCallable());
        QVERIFY(boostFn.isCallable());

        QJSValue store = emptyFn.call();
        const double now = static_cast<double>(QDateTime::currentMSecsSinceEpoch());
        const double initialBoost = boostFn.call({store, QStringLiteral("app:firefox"), QStringLiteral("fire"), now}).toNumber();
        QCOMPARE(initialBoost, 0.0);

        store = recordFn.call({store, QStringLiteral("app:firefox"), QStringLiteral("fire"), now});
        const double learnedBoost = boostFn.call({store, QStringLiteral("app:firefox"), QStringLiteral("fire"), now}).toNumber();
        QVERIFY(learnedBoost > 0.0);
    }

    void testDesktopAppLauncherSanitization()
    {
        const QJSValue sanitizeFn = m_engine.globalObject().property(QStringLiteral("sanitizeCommand"));
        QVERIFY(sanitizeFn.isCallable());

        QJSValue input = m_engine.newArray(4);
        input.setProperty(0, QStringLiteral("firefox"));
        input.setProperty(1, QStringLiteral("--private-window"));
        input.setProperty(2, QStringLiteral("%u"));
        input.setProperty(3, QStringLiteral("%F"));

        QJSValue sanitized = sanitizeFn.call({input});
        QVERIFY(sanitized.isArray());
        QCOMPARE(sanitized.property(QStringLiteral("length")).toInt(), 2);
        QCOMPARE(sanitized.property(0).toString(), QStringLiteral("firefox"));
        QCOMPARE(sanitized.property(1).toString(), QStringLiteral("--private-window"));
    }
};

QTEST_MAIN(SpotlightTests)
#include "spotlight_tests.moc"
